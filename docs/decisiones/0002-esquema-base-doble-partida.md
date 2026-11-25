# 0002 — Esquema base: libro contable con doble partida

- Estado: aceptada
- Fecha: 2026-11-25

## Contexto

Otto registra los movimientos de todas las cuentas de una persona (bancos, Mercado Pago, efectivo, broker, tarjetas) en un único libro. La app **no mueve dinero real**: una "transferencia" es registrar que la persona pasó plata entre sus propias cuentas por fuera de la app. Pagarle a otra persona es un gasto, no una transferencia.

Necesitamos que los reportes no cuenten dos veces la misma plata (por ejemplo, el pago del resumen de la tarjeta no es un gasto nuevo) y que los saldos no se puedan desincronizar.

## Decisión

### Modelo

Cada movimiento es una `transaction` con 2 o más `entries` (asientos). Cada asiento apunta a **una cuenta o a una categoría** (exactamente una de las dos) y tiene un monto `bigint` en la unidad mínima, positivo si entra plata a ese lugar y negativo si sale. **Los asientos de una transacción suman cero por moneda.**

| Caso                        | Asientos                                     |
| --------------------------- | -------------------------------------------- |
| Transferencia MP → banco    | MP −50.000 · Banco +50.000                   |
| Gasto con MP                | MP −20.000 · Supermercado +20.000            |
| Ingreso                     | Sueldo −800.000 · Banco +800.000             |
| Transferencia con comisión  | MP −50.300 · Banco +50.000 · Comisiones +300 |
| Compra con tarjeta          | Tarjeta −30.000 · Ropa +30.000               |
| Pago del resumen            | Banco −30.000 · Tarjeta +30.000              |
| Saldo inicial de una cuenta | Saldo inicial −100.000 · Banco +100.000      |

Una transacción sin asientos en categorías es una transferencia: no aparece en reportes de gastos ni ingresos.

### Tablas

- `profiles`: una fila por usuario (`id` = `auth.users.id`). No se llama `users` para no confundirla con `auth.users`.
- `accounts`: `type` (`bank` | `wallet` | `cash` | `broker` | `credit_card`) y `currency` (`ARS` | `USD`). Las tarjetas tienen saldo negativo cuando se debe.
- `categories`: separadas de las cuentas porque simplifica la UI y los reportes. `kind`: `income` | `expense` | `opening`. La categoría `opening` ("Saldo inicial") es del sistema: una por usuario, no se crea ni se borra desde la app, y los reportes la ignoran.
- `transactions`: `occurred_at` (UTC), `description`, `source` (`manual` | `import` | `email` | `assistant`), `external_id`, `voided_at`. Único `(user_id, source, external_id)`.
- `entries`: `account_id` XOR `category_id`, `amount bigint <> 0`, `currency`.
- Vista `account_balances` (`security_invoker`): saldo = suma de asientos de transacciones no anuladas. No se guarda el saldo en una columna.

### Invariantes que impone la base

- **Suma cero por moneda, al menos dos asientos y al menos uno en una cuenta**: constraint trigger diferido sobre `entries`. Las funciones de escritura lo fuerzan a correr antes de devolver (`set constraints ... immediate`) para que el error le llegue al cliente.
- **Moneda del asiento = moneda de la cuenta, y cuenta del mismo usuario**: FK compuesta `(account_id, user_id, currency)` → `accounts`.
- **Asiento del mismo usuario que su transacción**: FK compuesta `(transaction_id, user_id)` → `transactions`. Igual para categorías: `(category_id, user_id)` → `categories`.
- **RLS en las cinco tablas**, aislando por `user_id`.

### Escrituras del libro solo por funciones

`authenticated` puede leer `transactions` y `entries`, pero no escribirlas. Las escrituras pasan por tres funciones RPC:

- `registrar_transaccion(occurred_at, description, entries, source, external_id)`: idempotente; si ya existe `(source, external_id)` devuelve la transacción existente sin duplicar.
- `editar_transaccion(id, occurred_at, description, entries)`: reemplaza los asientos en una sola operación y vuelve a validar.
- `anular_transaccion(id)`: marca `voided_at`; no borra. Así, reimportar el mismo archivo o mail no vuelve a crear un movimiento que el usuario anuló.

Las tres son `SECURITY DEFINER` con `search_path = ''`, usan siempre `auth.uid()` (nunca reciben un `user_id`), solo las ejecuta `authenticated` y dependen de las FKs compuestas para rechazar cuentas o categorías de otro usuario.

Cuentas y categorías sí se escriben directo con RLS: no tienen invariantes entre filas.

### Alta de usuario

Un trigger sobre `auth.users` crea el perfil y las categorías por defecto. La migración hace lo mismo para los usuarios que ya existen.

### Tests

Tests de base con pgTAP (`supabase test db`): suma cero, moneda de la cuenta, mínimo de asientos, idempotencia, editar/anular, aislamiento entre usuarios por RLS y rechazo de escrituras directas. Corren en CI contra una base local levantada con la Supabase CLI.

## Fuera de alcance

- **Movimientos pendientes del asistente** (regla 4): van en una tabla propia del asistente; al confirmarse se registran con `source = 'assistant'`.
- **Compra/venta de dólares**: el invariante "suma cero por moneda" ya lo permite con una categoría de conversión por moneda y la cotización fechada; se modela con esa feature.
- **Tenencias del broker** (acciones, bonos): por ahora una cuenta `broker` solo registra plata.

## Consecuencias

- El saldo de una cuenta y cualquier reporte salen de sumar asientos: una sola fuente de verdad.
- Editar o importar nunca puede dejar el libro desbalanceado, aunque haya un bug en el cliente.
- Las funciones `SECURITY DEFINER` saltean RLS: cada una nueva debe usar `auth.uid()`, fijar `search_path` y tener tests de aislamiento.
