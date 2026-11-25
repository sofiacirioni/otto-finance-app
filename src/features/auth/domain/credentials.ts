import { z } from 'zod';

export const emailSchema = z
  .string()
  .trim()
  .toLowerCase()
  .pipe(z.email({ error: 'Ingresá un mail válido.' }));

// Supabase permite configurar el largo del código entre 6 y 10 dígitos.
export const otpCodeSchema = z
  .string()
  .trim()
  .regex(/^\d{6,10}$/, { error: 'El código son solo números (6 a 10 dígitos).' });

export type ValidationResult<T> = { ok: true; value: T } | { ok: false; error: string };

function validate<T>(schema: z.ZodType<T>, input: string): ValidationResult<T> {
  const result = schema.safeParse(input);
  if (result.success) return { ok: true, value: result.data };
  return { ok: false, error: result.error.issues[0]?.message ?? 'Dato inválido.' };
}

export const validateEmail = (input: string) => validate(emailSchema, input);
export const validateOtpCode = (input: string) => validate(otpCodeSchema, input);
