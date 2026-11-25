# Otto — finanzas personales

App móvil (iOS + Android, Expo) que unifica cuentas (bancos, Mercado Pago, efectivo, broker) en un único libro contable con doble partida. Una mascota con IA registra operaciones por texto o voz, responde preguntas sobre los datos y resume noticias económicas. Público: Argentina. Portfolio.

Especificación completa: `docs/especificacion.md` (fuente de verdad del alcance y las etapas).

## Guía por capas

- **Expo / React Native / EAS**: seguir `AGENTS.md` (no duplicar acá). Antes de tocar cualquier API de Expo, leer los docs de la versión que figura en `package.json`.
- **Convenciones de producto y arquitectura**: este archivo.

## Reglas inviolables

Estas no se negocian. Si una tarea parece requerir romperlas, parar y preguntar.

1. **Plata en enteros, nunca `float`.** Todos los montos se guardan y transportan como enteros en la unidad mínima (centavos para ARS, cents para USD). Mostrar con formato solo en la capa de UI.
2. **Moneda por cuenta.** Cada `account` tiene su moneda (`ARS` | `USD`). Nunca mezclar monedas sin pasar por conversión explícita con cotización fechada.
3. **Doble partida.** Todo movimiento se expresa como `transaction` + N `entries` que suman cero. Una transferencia MP → banco es un movimiento entre cuentas, no un gasto. Ningún `INSERT` directo a `entries` sin pasar por el servicio de transacciones.
4. **La IA propone, el usuario confirma.** Cualquier registro generado por el asistente (texto/voz/email) entra como _pendiente_ y solo se persiste al libro cuando el usuario confirma la tarjeta. La IA nunca inventa números: los obtiene con _tool calling_ contra la base.
5. **Validar todo lo que cruza un borde con Zod.** Formularios, respuestas de IA, payloads de Edge Functions, parsers de CSV/PDF/email. Si no está validado, no entra al dominio.
6. **RLS en todas las tablas.** Toda tabla nueva nace con política de Row Level Security que aísla por `user_id`. Las migraciones que crean tablas sin RLS no se mergean.
7. **Secretos fuera del repo y fuera del cliente.** Claves de IA, tokens de Gmail, credenciales de servicios: solo en variables de entorno del servidor (Supabase Edge Functions). El bundle del cliente nunca las ve.
8. **Idempotencia en los conectores.** Cada movimiento importado guarda `source` (`manual` | `import` | `email` | ...) y `external_id`. Reimportar el mismo archivo o leer dos veces el mismo mail no duplica.
9. **Sin recomendaciones de inversión.** La mascota informa, nunca aconseja. Sin scraping de home banking ni ejecución de pagos: la app es solo lectura y registro.

## Arquitectura

**Cada fuente es un conector intercambiable que vuelca al mismo libro contable.** Open Finance (BCRA) queda como un conector futuro; la interfaz debe permitirlo sin tocar el resto.

Flujo de un movimiento:

```
barra (texto/voz) ─┐
importar CSV/PDF ──┼─► conector ─► normalización ─► tarjeta de confirmación ─► libro contable (PG, doble partida)
mails (Gmail) ─────┘                                                               │
Open Finance (futuro) ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘
                                                                                   ├─► dashboard / reportes
                                                                                   └─► mascota (chat)
```

## Estructura de carpetas

Organización **por feature**, no por tipo. La lógica de negocio vive separada de la UI y se testea sola.

```
src/
  app/              # rutas de Expo Router (solo pantallas y layouts)
  features/
    accounts/
    transactions/
    assistant/      # barra, tool calling, mascota
    news/
    ...
    <feature>/
      ui/           # componentes y screens de la feature
      domain/       # tipos, invariantes, lógica pura (testeable sin RN)
      data/         # repos, llamadas a Supabase, parsers
      index.ts      # API pública de la feature
  components/       # UI compartida entre features
  hooks/
  constants/
  lib/              # utilidades transversales (formato de plata, fechas, etc.)
supabase/
  migrations/       # SQL versionado (Supabase CLI)
  functions/        # Edge Functions (IA, Gmail, transcripción)
docs/
  especificacion.md
  decisiones/       # ADRs cortos (uno por decisión relevante)
```

Reglas:

- `src/app/` solo contiene rutas y layouts. Nada de lógica de dominio ni componentes reusables ahí.
- Una feature no importa archivos internos de otra feature: solo su `index.ts`.
- Dominio puro (sin imports de `react-native` ni `expo-*`) para poder testearlo rápido con Jest.

## Datos y dinero

- Tablas base: `users`, `accounts`, `categories`, `transactions`, `entries`. Montos siempre `bigint` en la unidad mínima.
- Fechas en UTC en la base; convertir a zona del usuario (`America/Argentina/Buenos_Aires`) solo al mostrar.
- Migraciones con Supabase CLI. Regenerar tipos de TS tras cada migración y commitearlos.
- Al modelar una tabla nueva: política RLS, índices por `user_id`, columna `source` + `external_id` si recibe datos externos.

## Asistente (barra de texto/voz)

- Herramientas (_tool calling_): `registrar_movimiento`, `consultar_movimientos`, `resumen_por_categoria`, `saldo_de_cuentas`. Las consultas pasan por SQL real; la IA solo interpreta y redacta.
- Voz: grabar con `expo-audio`, transcribir en el servidor (Whisper o similar), seguir el mismo flujo que el texto.
- Mascota: estados con Rive (feliz, pensando, festejando, preocupada). Los estados se derivan del contexto, no los decide la IA libremente.
- Toda respuesta de IA pasa por un schema Zod antes de alimentar la UI.

## Git y PRs

- Una rama y un PR por funcionalidad. PRs chicos y revisables.
- **Conventional commits** (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- CI corre `lint`, `tsc --noEmit` y `jest` en cada PR. No se mergea en rojo.
- Decisiones arquitectónicas relevantes → ADR corto en `docs/decisiones/NNNN-titulo.md` _antes_ de implementar.

## Comandos

Los comandos de Expo/EAS están en `AGENTS.md`. Específicos del proyecto:

```bash
npx expo lint          # lint (requerido antes de PR)
npx tsc --noEmit       # typecheck (requerido antes de PR)
npx jest               # tests unitarios
```

Correr `lint` + `typecheck` + `jest` antes de declarar una tarea terminada.

## Al escribir código

- Preferir módulos de Expo recomendados antes que librerías de terceros. Verificar en los docs de la versión actual.
- No introducir abstracciones "por si acaso". El spec es la lista de features; no inventar scope.
- Si una tarea toca dinero, confirmación de IA, RLS o conectores: releer las _reglas inviolables_ antes de proponer el cambio.
- Al tocar una tabla o un flujo de dominio, actualizar los tests del dominio en la misma PR.

## Etapa actual

**Etapa 0 — Base del proyecto.** El repo está recién iniciado: template de Expo, aún sin Supabase ni features de negocio. Las próximas tareas son setup (ESLint/Prettier/Jest/CI, Supabase + Auth + esquema base, primer build EAS). Ver `docs/especificacion.md` para el detalle de etapas 1 a 4.

## Fuera de alcance

- Conexión directa con bancos/billeteras por scraping o credenciales. Open Finance queda previsto como conector futuro.
- Pagos o transferencias desde la app.
- Recomendaciones de inversión.

Si una tarea implica algo de esta lista, confirmar con el usuario antes de avanzar.
