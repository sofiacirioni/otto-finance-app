# Setup de Supabase

Pasos manuales en el dashboard de Supabase para dejar el proyecto funcionando. El porqué del login por código está en [ADR 0001](decisiones/0001-auth-supabase-codigo-por-mail.md).

## 1. Proyecto

- **New project** → name `otto`, region **South America (São Paulo)**.
- Database password: generarla y guardarla en un gestor de contraseñas (no en el repo).
- **Data access**: activar las tres opciones (Data API, grant automático a tablas nuevas, RLS automático en tablas nuevas). Igual, cada migración declara RLS y políticas explícitamente.
- **GitHub integration**: por ahora no. Se evalúa cuando existan migraciones y CI que las pruebe.

## 2. Variables de entorno

En **Project Settings → API Keys** copiar la Project URL y la **publishable key** (nunca la secret/service_role).

```bash
cp .env.example .env.local   # .env.local está en .gitignore
```

## 3. SMTP propio (requerido para editar plantillas)

Supabase no deja editar las plantillas de mail con el SMTP integrado. Usamos Resend:

1. Crear cuenta en resend.com y una API key con _Sending access_ (secreta: no va al repo).
2. **Authentication → Emails → SMTP Settings** → _Enable custom SMTP_:

   | Campo        | Valor                   |
   | ------------ | ----------------------- |
   | Sender email | `onboarding@resend.dev` |
   | Sender name  | `Otto`                  |
   | Host         | `smtp.resend.com`       |
   | Port         | `465`                   |
   | Username     | `resend`                |
   | Password     | API key de Resend       |

> Sin dominio verificado, Resend solo envía al mail de la cuenta de Resend. Alcanza para desarrollo; antes de que otros usen la app hay que verificar un dominio y cambiar el remitente.

## 4. Plantilla de mail con código

**Authentication → Emails → Templates → Magic Link** (y también **Confirm signup**):

```html
<h2>Tu código para entrar a Otto</h2>
<p>Ingresá este código en la app: <strong>{{ .Token }}</strong></p>
<p>Vence en 1 hora. Si no lo pediste, ignorá este mail.</p>
```

## 5. Provider Email

**Authentication → Sign In / Providers → Email**: habilitado, _Email OTP Length_ = 6.

## Verificación

`npx expo start` → ingresar mail → llega el código → entrar → el home muestra el mail. Cerrar y reabrir la app mantiene la sesión.
