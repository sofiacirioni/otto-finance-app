-- Tests del esquema base (ADR 0002). Correr con: npx supabase test db
begin;
create extension if not exists pgtap with schema extensions;

select plan(36);

-- ---------------------------------------------------------------------------
-- Datos: dos usuarias (Ana y Beto) y sus cuentas
-- ---------------------------------------------------------------------------
-- Ana:  00000000-0000-0000-0000-00000000000a
--   MP (ARS)    aaaaaaaa-0000-0000-0000-000000000001
--   Banco (ARS) aaaaaaaa-0000-0000-0000-000000000002
--   Banco (USD) aaaaaaaa-0000-0000-0000-000000000003
-- Beto: 00000000-0000-0000-0000-00000000000b
--   Banco (ARS) bbbbbbbb-0000-0000-0000-000000000001

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'ana@otto.test'),
  ('00000000-0000-0000-0000-00000000000b', 'beto@otto.test');

select is(
  (select count(*)::int from pg_class
    where relnamespace = 'public'::regnamespace
      and relname in ('profiles', 'accounts', 'categories', 'transactions', 'entries')
      and relrowsecurity),
  5,
  'RLS activado en las cinco tablas'
);

select ok(
  exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-00000000000a'),
  'el alta de usuario crea el perfil'
);

select is(
  (select count(*)::int from public.categories
    where user_id = '00000000-0000-0000-0000-00000000000a' and kind = 'opening'),
  1,
  'el alta de usuario crea una única categoría "Saldo inicial"'
);

insert into public.accounts (id, user_id, name, type, currency) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'Mercado Pago', 'wallet', 'ARS'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000a', 'Banco', 'bank', 'ARS'),
  ('aaaaaaaa-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000a', 'Banco USD', 'bank', 'USD'),
  ('bbbbbbbb-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'Banco', 'bank', 'ARS');

-- ---------------------------------------------------------------------------
-- Como Ana
-- ---------------------------------------------------------------------------
do $$ begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000a","role":"authenticated"}', true);
end $$;
set local role authenticated;

select lives_ok(
  $$ select public.registrar_transaccion(now(), 'Saldo inicial MP', jsonb_build_array(
       jsonb_build_object('category_id', (select id from public.categories where kind = 'opening'),
                          'amount', -12000000, 'currency', 'ARS'),
       jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'amount', 12000000, 'currency', 'ARS'))) $$,
  'registra un saldo inicial contra la categoría "Saldo inicial"'
);

select lives_ok(
  $$ select public.registrar_transaccion(now(), 'Paso plata de MP al banco', '[
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": -5000000, "currency": "ARS"},
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000002", "amount":  5000000, "currency": "ARS"}
     ]'::jsonb) $$,
  'registra una transferencia balanceada entre cuentas propias'
);

select is(
  (select balance from public.account_balances where account_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  7000000::bigint,
  'saldo de MP: 120.000 − 50.000'
);

select is(
  (select balance from public.account_balances where account_id = 'aaaaaaaa-0000-0000-0000-000000000002'),
  5000000::bigint,
  'saldo del banco: +50.000'
);

select throws_like(
  $$ select public.registrar_transaccion(now(), 'Desbalanceada', '[
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": -100, "currency": "ARS"},
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000002", "amount":   90, "currency": "ARS"}
     ]'::jsonb) $$,
  '%no suman cero%',
  'rechaza asientos que no suman cero'
);

select throws_like(
  $$ select public.registrar_transaccion(now(), 'Un solo asiento', '[
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": 100, "currency": "ARS"}
     ]'::jsonb) $$,
  '%al menos dos asientos%',
  'rechaza una transacción con un solo asiento'
);

select throws_like(
  $$ select public.registrar_transaccion(now(), 'Solo categorías', jsonb_build_array(
       jsonb_build_object('category_id', (select id from public.categories where name = 'Sueldo'),
                          'amount', -100, 'currency', 'ARS'),
       jsonb_build_object('category_id', (select id from public.categories where name = 'Supermercado'),
                          'amount', 100, 'currency', 'ARS'))) $$,
  '%al menos un asiento en una cuenta%',
  'rechaza una transacción sin asientos en cuentas'
);

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Dólares en cuenta en pesos', '[
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": -100, "currency": "USD"},
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000003", "amount":  100, "currency": "USD"}
     ]'::jsonb) $$,
  '23503',
  null,
  'rechaza un asiento cuya moneda no es la de su cuenta'
);

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Cuenta y categoría a la vez', jsonb_build_array(
       jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000001',
                          'category_id', (select id from public.categories where name = 'Supermercado'),
                          'amount', -100, 'currency', 'ARS'),
       jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000002', 'amount', 100, 'currency', 'ARS'))) $$,
  '23514',
  null,
  'rechaza un asiento que apunta a cuenta y categoría a la vez'
);

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Monto cero', '[
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": 0, "currency": "ARS"},
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000002", "amount": 0, "currency": "ARS"}
     ]'::jsonb) $$,
  '23514',
  null,
  'rechaza asientos con monto cero'
);

-- Idempotencia (regla 8)
select lives_ok(
  $$ select public.registrar_transaccion(now(), 'Compra importada', jsonb_build_array(
       jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'amount', -150000, 'currency', 'ARS'),
       jsonb_build_object('category_id', (select id from public.categories where name = 'Supermercado'),
                          'amount', 150000, 'currency', 'ARS')), 'import', 'csv-0001') $$,
  'registra un movimiento importado con external_id'
);

select is(
  public.registrar_transaccion(now(), 'Compra importada', jsonb_build_array(
    jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'amount', -150000, 'currency', 'ARS'),
    jsonb_build_object('category_id', (select id from public.categories where name = 'Supermercado'),
                       'amount', 150000, 'currency', 'ARS')), 'import', 'csv-0001'),
  (select id from public.transactions where external_id = 'csv-0001'),
  'reimportar el mismo external_id devuelve la transacción existente'
);

select is(
  (select count(*)::int from public.entries e
     join public.transactions t on t.id = e.transaction_id
    where t.external_id = 'csv-0001'),
  2,
  'reimportar no duplica asientos'
);

-- Editar
select lives_ok(
  $$ select public.editar_transaccion(
       (select id from public.transactions where description = 'Paso plata de MP al banco'),
       now(), 'Paso plata de MP al banco (con comisión)', jsonb_build_array(
         jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000001', 'amount', -5030000, 'currency', 'ARS'),
         jsonb_build_object('account_id', 'aaaaaaaa-0000-0000-0000-000000000002', 'amount', 5000000, 'currency', 'ARS'),
         jsonb_build_object('category_id', (select id from public.categories where name = 'Comisiones e impuestos'),
                            'amount', 30000, 'currency', 'ARS'))) $$,
  'edita una transacción reemplazando sus asientos'
);

select is(
  (select balance from public.account_balances where account_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  (12000000 - 5030000 - 150000)::bigint,
  'el saldo refleja la edición'
);

select throws_like(
  $$ select public.editar_transaccion(
       (select id from public.transactions where description like 'Paso plata%'),
       now(), 'Editada mal', '[
         {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": -100, "currency": "ARS"},
         {"account_id": "aaaaaaaa-0000-0000-0000-000000000002", "amount":   99, "currency": "ARS"}
       ]'::jsonb) $$,
  '%no suman cero%',
  'editar también valida la suma cero'
);

-- Anular
select lives_ok(
  $$ select public.anular_transaccion((select id from public.transactions where description like 'Paso plata%')) $$,
  'anula una transacción'
);

select is(
  (select balance from public.account_balances where account_id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  (12000000 - 150000)::bigint,
  'los saldos ignoran las transacciones anuladas'
);

select throws_ok(
  $$ select public.anular_transaccion((select id from public.transactions where description like 'Paso plata%')) $$,
  'P0002',
  null,
  'no se puede anular dos veces'
);

select throws_ok(
  $$ select public.editar_transaccion(
       (select id from public.transactions where description like 'Paso plata%'),
       now(), 'Editar anulada', '[
         {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount": -100, "currency": "ARS"},
         {"account_id": "aaaaaaaa-0000-0000-0000-000000000002", "amount":  100, "currency": "ARS"}
       ]'::jsonb) $$,
  'P0002',
  null,
  'no se puede editar una transacción anulada'
);

-- Escrituras directas (regla 3)
select throws_ok(
  $$ insert into public.transactions (user_id, occurred_at, description)
     values ('00000000-0000-0000-0000-00000000000a', now(), 'Directa') $$,
  '42501',
  null,
  'no se puede insertar directo en transactions'
);

select throws_ok(
  $$ insert into public.entries (transaction_id, user_id, account_id, amount, currency)
     values ((select id from public.transactions limit 1), '00000000-0000-0000-0000-00000000000a',
             'aaaaaaaa-0000-0000-0000-000000000001', 100, 'ARS') $$,
  '42501',
  null,
  'no se puede insertar directo en entries'
);

select throws_ok(
  $$ insert into public.categories (name, kind) values ('Otro saldo inicial', 'opening') $$,
  '42501',
  null,
  'no se puede crear otra categoría "Saldo inicial"'
);

-- ---------------------------------------------------------------------------
-- Como Beto: no ve ni toca nada de Ana
-- ---------------------------------------------------------------------------
-- Guardar el id de una transacción de Ana (Beto no la puede leer por RLS).
reset role;
do $$ begin
  perform set_config('test.ana_tx', (select id::text from public.transactions where external_id = 'csv-0001'), true);
  perform set_config('test.ana_cat', (select id::text from public.categories
                                       where user_id = '00000000-0000-0000-0000-00000000000a'
                                         and name = 'Supermercado'), true);
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-00000000000b","role":"authenticated"}', true);
end $$;
set local role authenticated;

select is((select count(*)::int from public.transactions), 0, 'Beto no ve transacciones de Ana');
select is((select count(*)::int from public.entries), 0, 'Beto no ve asientos de Ana');
select is((select count(*)::int from public.accounts), 1, 'Beto solo ve su propia cuenta');
select is((select count(*)::int from public.account_balances), 1, 'Beto solo ve el saldo de su cuenta');

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Usar cuenta ajena', '[
       {"account_id": "bbbbbbbb-0000-0000-0000-000000000001", "amount": -100, "currency": "ARS"},
       {"account_id": "aaaaaaaa-0000-0000-0000-000000000001", "amount":  100, "currency": "ARS"}
     ]'::jsonb) $$,
  '23503',
  null,
  'Beto no puede registrar asientos en una cuenta de Ana'
);

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Usar categoría ajena', jsonb_build_array(
       jsonb_build_object('account_id', 'bbbbbbbb-0000-0000-0000-000000000001', 'amount', -100, 'currency', 'ARS'),
       jsonb_build_object('category_id', current_setting('test.ana_cat'),
                          'amount', 100, 'currency', 'ARS'))) $$,
  '23503',
  null,
  'Beto no puede usar una categoría de Ana'
);

select throws_ok(
  $$ select public.anular_transaccion(current_setting('test.ana_tx')::uuid) $$,
  'P0002',
  null,
  'Beto no puede anular una transacción de Ana'
);

select throws_ok(
  $$ select public.editar_transaccion(current_setting('test.ana_tx')::uuid, now(), 'Editar ajena', '[
       {"account_id": "bbbbbbbb-0000-0000-0000-000000000001", "amount": -100, "currency": "ARS"},
       {"account_id": "bbbbbbbb-0000-0000-0000-000000000001", "amount":  100, "currency": "ARS"}
     ]'::jsonb) $$,
  'P0002',
  null,
  'Beto no puede editar una transacción de Ana'
);

-- ---------------------------------------------------------------------------
-- Sin sesión (anon)
-- ---------------------------------------------------------------------------
reset role;
set local role anon;

select throws_ok(
  $$ select public.registrar_transaccion(now(), 'Anon', '[]'::jsonb) $$,
  '42501',
  null,
  'anon no puede ejecutar registrar_transaccion'
);

select throws_ok(
  $$ select count(*) from public.transactions $$,
  '42501',
  null,
  'anon no puede leer transactions'
);

select * from finish();
rollback;
