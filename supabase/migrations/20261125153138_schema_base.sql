-- Esquema base: libro contable con doble partida.
-- Decisiones y ejemplos: docs/decisiones/0002-esquema-base-doble-partida.md

-- ---------------------------------------------------------------------------
-- Tipos
-- ---------------------------------------------------------------------------

create type public.currency_code as enum ('ARS', 'USD');
create type public.account_type as enum ('bank', 'wallet', 'cash', 'broker', 'credit_card');
create type public.category_kind as enum ('income', 'expense', 'opening');
create type public.transaction_source as enum ('manual', 'import', 'email', 'assistant');

-- Funciones internas (triggers, alta de usuario): fuera del esquema expuesto por la API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Tablas
-- ---------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text check (char_length(display_name) <= 60),
  timezone text not null default 'America/Argentina/Buenos_Aires',
  created_at timestamptz not null default now()
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  type public.account_type not null,
  currency public.currency_code not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  -- Destino de la FK compuesta de entries: misma cuenta, mismo usuario, misma moneda.
  unique (id, user_id, currency)
);

create unique index accounts_user_name_active_key
  on public.accounts (user_id, lower(btrim(name)))
  where archived_at is null;

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  kind public.category_kind not null,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create unique index categories_user_kind_name_active_key
  on public.categories (user_id, kind, lower(btrim(name)))
  where archived_at is null;

-- Una sola categoría "Saldo inicial" por usuario.
create unique index categories_user_opening_key
  on public.categories (user_id)
  where kind = 'opening';

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  occurred_at timestamptz not null,
  description text not null check (char_length(btrim(description)) between 1 and 200),
  source public.transaction_source not null default 'manual',
  external_id text check (external_id is null or char_length(external_id) between 1 and 200),
  voided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  -- Idempotencia de conectores (regla 8). Los NULL no chocan entre sí.
  unique (user_id, source, external_id)
);

create index transactions_user_occurred_at_idx
  on public.transactions (user_id, occurred_at desc);

create table public.entries (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  account_id uuid,
  category_id uuid,
  amount bigint not null check (amount <> 0),
  currency public.currency_code not null,
  constraint entries_account_xor_category check (num_nonnulls(account_id, category_id) = 1),
  constraint entries_transaction_fkey foreign key (transaction_id, user_id)
    references public.transactions (id, user_id) on delete cascade,
  constraint entries_account_fkey foreign key (account_id, user_id, currency)
    references public.accounts (id, user_id, currency),
  constraint entries_category_fkey foreign key (category_id, user_id)
    references public.categories (id, user_id)
);

create index entries_transaction_id_idx on public.entries (transaction_id);
create index entries_user_id_idx on public.entries (user_id);
create index entries_account_id_idx on public.entries (account_id) where account_id is not null;
create index entries_category_id_idx on public.entries (category_id) where category_id is not null;

-- ---------------------------------------------------------------------------
-- Invariante de doble partida
-- ---------------------------------------------------------------------------

-- Por transacción: al menos 2 asientos, al menos 1 en una cuenta, y suma cero por moneda.
-- security definer: también corre cuando Auth borra un usuario y los asientos caen en cascada.
create function private.check_transaction_balance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction_id uuid := coalesce(new.transaction_id, old.transaction_id);
  v_entry_count int;
  v_account_entry_count int;
  v_unbalanced_currency public.currency_code;
begin
  -- Borrada en cascada junto con la transacción: nada que validar.
  if not exists (select 1 from public.transactions where id = v_transaction_id) then
    return null;
  end if;

  select count(*), count(account_id)
    into v_entry_count, v_account_entry_count
    from public.entries
   where transaction_id = v_transaction_id;

  if v_entry_count < 2 then
    raise exception 'La transacción % necesita al menos dos asientos', v_transaction_id
      using errcode = 'P0001', hint = 'otto:min_entries';
  end if;

  if v_account_entry_count = 0 then
    raise exception 'La transacción % necesita al menos un asiento en una cuenta', v_transaction_id
      using errcode = 'P0001', hint = 'otto:no_account_entry';
  end if;

  select currency
    into v_unbalanced_currency
    from public.entries
   where transaction_id = v_transaction_id
   group by currency
  having sum(amount) <> 0
   limit 1;

  if v_unbalanced_currency is not null then
    raise exception 'Los asientos de la transacción % no suman cero en %', v_transaction_id, v_unbalanced_currency
      using errcode = 'P0001', hint = 'otto:unbalanced';
  end if;

  return null;
end;
$$;

create constraint trigger entries_balanced
  after insert or update or delete on public.entries
  deferrable initially deferred
  for each row execute function private.check_transaction_balance();

-- ---------------------------------------------------------------------------
-- Saldos
-- ---------------------------------------------------------------------------

create view public.account_balances
with (security_invoker = true)
as
select
  a.id as account_id,
  a.user_id,
  a.currency,
  coalesce(sum(e.amount) filter (where t.voided_at is null), 0)::bigint as balance
from public.accounts a
left join public.entries e on e.account_id = a.id
left join public.transactions t on t.id = e.transaction_id
group by a.id;

-- ---------------------------------------------------------------------------
-- Alta de usuario: perfil + categorías por defecto
-- ---------------------------------------------------------------------------

create function private.seed_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id) values (p_user_id)
  on conflict (id) do nothing;

  insert into public.categories (user_id, name, kind)
  select p_user_id, c.name, c.kind::public.category_kind
    from (values
      ('Saldo inicial', 'opening'),
      ('Sueldo', 'income'),
      ('Trabajos independientes', 'income'),
      ('Intereses y rendimientos', 'income'),
      ('Otros ingresos', 'income'),
      ('Supermercado', 'expense'),
      ('Comida y delivery', 'expense'),
      ('Transporte', 'expense'),
      ('Servicios', 'expense'),
      ('Alquiler y expensas', 'expense'),
      ('Salud', 'expense'),
      ('Ocio', 'expense'),
      ('Ropa', 'expense'),
      ('Educación', 'expense'),
      ('Comisiones e impuestos', 'expense'),
      ('Otros gastos', 'expense')
    ) as c (name, kind)
   where not exists (select 1 from public.categories where user_id = p_user_id);
end;
$$;

create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.seed_user(new.id);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Usuarios que ya existían antes de esta migración.
select private.seed_user(id) from auth.users;

-- ---------------------------------------------------------------------------
-- Escrituras del libro (únicas puertas de entrada a transactions/entries)
-- ---------------------------------------------------------------------------

-- p_entries: [{ "account_id": uuid | null, "category_id": uuid | null, "amount": int, "currency": "ARS" | "USD" }]
create function public.registrar_transaccion(
  p_occurred_at timestamptz,
  p_description text,
  p_entries jsonb,
  p_source public.transaction_source default 'manual',
  p_external_id text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_transaction_id uuid;
begin
  if v_user_id is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  if jsonb_typeof(p_entries) is distinct from 'array' then
    raise exception 'p_entries debe ser un array' using errcode = '22023';
  end if;

  -- Diferir hasta tener todos los asientos (otra llamada en la misma transacción pudo dejarlo inmediato).
  set constraints public.entries_balanced deferred;

  insert into public.transactions (user_id, occurred_at, description, source, external_id)
  values (v_user_id, p_occurred_at, p_description, p_source, p_external_id)
  on conflict (user_id, source, external_id) do nothing
  returning id into v_transaction_id;

  -- Ya importada: devolver la existente sin duplicar (regla 8).
  if v_transaction_id is null then
    select id into v_transaction_id
      from public.transactions
     where user_id = v_user_id and source = p_source and external_id = p_external_id;
    return v_transaction_id;
  end if;

  insert into public.entries (transaction_id, user_id, account_id, category_id, amount, currency)
  select v_transaction_id, v_user_id, e.account_id, e.category_id, e.amount, e.currency
    from jsonb_to_recordset(p_entries)
      as e (account_id uuid, category_id uuid, amount bigint, currency public.currency_code);

  -- Validar la doble partida ahora, no al commit, para devolver el error al cliente.
  set constraints public.entries_balanced immediate;

  return v_transaction_id;
end;
$$;

create function public.editar_transaccion(
  p_transaction_id uuid,
  p_occurred_at timestamptz,
  p_description text,
  p_entries jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  if jsonb_typeof(p_entries) is distinct from 'array' then
    raise exception 'p_entries debe ser un array' using errcode = '22023';
  end if;

  -- Diferir: entre el delete y el insert la transacción queda sin asientos.
  set constraints public.entries_balanced deferred;

  update public.transactions
     set occurred_at = p_occurred_at,
         description = p_description,
         updated_at = now()
   where id = p_transaction_id
     and user_id = v_user_id
     and voided_at is null;

  if not found then
    raise exception 'Transacción inexistente o anulada'
      using errcode = 'P0002', hint = 'otto:transaction_not_found';
  end if;

  delete from public.entries where transaction_id = p_transaction_id;

  insert into public.entries (transaction_id, user_id, account_id, category_id, amount, currency)
  select p_transaction_id, v_user_id, e.account_id, e.category_id, e.amount, e.currency
    from jsonb_to_recordset(p_entries)
      as e (account_id uuid, category_id uuid, amount bigint, currency public.currency_code);

  set constraints public.entries_balanced immediate;
end;
$$;

create function public.anular_transaccion(p_transaction_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'No autenticado' using errcode = '42501';
  end if;

  update public.transactions
     set voided_at = now(),
         updated_at = now()
   where id = p_transaction_id
     and user_id = v_user_id
     and voided_at is null;

  if not found then
    raise exception 'Transacción inexistente o ya anulada'
      using errcode = 'P0002', hint = 'otto:transaction_not_found';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Permisos
-- ---------------------------------------------------------------------------

revoke all on public.profiles, public.accounts, public.categories, public.transactions, public.entries,
  public.account_balances from anon, authenticated;

grant select, update (display_name, timezone) on public.profiles to authenticated;
grant select, insert, update, delete on public.accounts to authenticated;
grant select, insert, update, delete on public.categories to authenticated;
grant select on public.transactions, public.entries, public.account_balances to authenticated;

revoke all on function private.check_transaction_balance() from public, anon, authenticated;
revoke all on function private.seed_user(uuid) from public, anon, authenticated;
revoke all on function private.handle_new_user() from public, anon, authenticated;

revoke all on function public.registrar_transaccion(timestamptz, text, jsonb, public.transaction_source, text)
  from public, anon;
revoke all on function public.editar_transaccion(uuid, timestamptz, text, jsonb) from public, anon;
revoke all on function public.anular_transaccion(uuid) from public, anon;
grant execute on function public.registrar_transaccion(timestamptz, text, jsonb, public.transaction_source, text)
  to authenticated;
grant execute on function public.editar_transaccion(uuid, timestamptz, text, jsonb) to authenticated;
grant execute on function public.anular_transaccion(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.categories enable row level security;
alter table public.transactions enable row level security;
alter table public.entries enable row level security;

create policy "profiles: ver el propio" on public.profiles
  for select to authenticated using (id = (select auth.uid()));
create policy "profiles: editar el propio" on public.profiles
  for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "accounts: ver propias" on public.accounts
  for select to authenticated using (user_id = (select auth.uid()));
create policy "accounts: crear propias" on public.accounts
  for insert to authenticated with check (user_id = (select auth.uid()));
create policy "accounts: editar propias" on public.accounts
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "accounts: borrar propias" on public.accounts
  for delete to authenticated using (user_id = (select auth.uid()));

-- La categoría "Saldo inicial" (opening) es del sistema: se ve, pero no se toca.
create policy "categories: ver propias" on public.categories
  for select to authenticated using (user_id = (select auth.uid()));
create policy "categories: crear propias" on public.categories
  for insert to authenticated with check (user_id = (select auth.uid()) and kind <> 'opening');
create policy "categories: editar propias" on public.categories
  for update to authenticated
  using (user_id = (select auth.uid()) and kind <> 'opening')
  with check (user_id = (select auth.uid()) and kind <> 'opening');
create policy "categories: borrar propias" on public.categories
  for delete to authenticated using (user_id = (select auth.uid()) and kind <> 'opening');

-- Solo lectura: las escrituras pasan por registrar/editar/anular_transaccion.
create policy "transactions: ver propias" on public.transactions
  for select to authenticated using (user_id = (select auth.uid()));
create policy "entries: ver propias" on public.entries
  for select to authenticated using (user_id = (select auth.uid()));
