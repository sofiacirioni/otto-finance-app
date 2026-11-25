# 0001 — Auth con Supabase: código de un solo uso por mail

- Estado: aceptada
- Fecha: 2026-11-25

## Contexto

Otto necesita login por mail desde el día uno: todas las tablas aíslan por `user_id` con RLS, así que sin sesión no hay datos. Supabase ofrece por mail dos variantes sin contraseña:

1. **Magic link**: el mail trae un link que vuelve a abrir la app (deep link) con los tokens.
2. **Código OTP**: el mail trae un código numérico que el usuario tipea en la app.

## Decisión

Usamos **código OTP por mail** (`signInWithOtp` + `verifyOtp({ type: 'email' })`), sin contraseña. El mismo flujo sirve para registrarse y para entrar.

- El cliente se crea con `@supabase/supabase-js` y la **publishable key** (pública por diseño; la seguridad la da RLS). La `service_role`/secret key nunca va al cliente.
- La sesión se persiste con `expo-sqlite/localStorage`, como recomienda la guía de Expo.
- Las rutas se protegen con `Stack.Protected` de Expo Router.

## Por qué no magic link

- El deep link depende del entorno: en Expo Go la URL es `exp://<ip>:8081`, en dev build `ottofinanceapp://`; hay que registrar cada una como redirect en Supabase y se rompe al cambiar de red.
- Si el usuario abre el mail en otro dispositivo (la compu), el link no puede volver a la app.
- El código funciona igual en Expo Go, dev build y producción, sin configuración extra.

## Consecuencias

- Hay que editar la plantilla de mail "Magic Link" en Supabase para que muestre `{{ .Token }}`.
- Supabase no permite editar plantillas con su SMTP integrado, así que desde desarrollo usamos un SMTP propio (Resend). Sin dominio verificado solo envía al mail de la cuenta; antes de publicar hay que verificar un dominio. Pasos en [`docs/setup-supabase.md`](../setup-supabase.md).
- Agregar OAuth (Google/Apple) más adelante es compatible: usa el mismo cliente y el mismo `onAuthStateChange`.
