// Traduce los códigos de error de Supabase Auth a mensajes para el usuario.
// https://supabase.com/docs/guides/auth/debugging/error-codes
const MESSAGES: Record<string, string> = {
  over_email_send_rate_limit:
    'Pediste muchos códigos seguidos. Esperá unos minutos y probá de nuevo.',
  over_request_rate_limit: 'Demasiados intentos. Esperá unos minutos y probá de nuevo.',
  otp_expired: 'El código venció o no es correcto. Pedí uno nuevo.',
  email_address_invalid: 'Ese mail no es válido.',
  signup_disabled: 'El registro de cuentas nuevas está deshabilitado.',
};

const FALLBACK = 'No pudimos completar el ingreso. Revisá tu conexión y probá de nuevo.';

export function authErrorMessage(code: string | undefined): string {
  return (code && MESSAGES[code]) || FALLBACK;
}
