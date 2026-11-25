import type { AuthError, Session } from '@supabase/supabase-js';

import { supabase } from '@/lib/supabase';

import { authErrorMessage } from '../domain/auth-errors';

export type AuthResult = { ok: true } | { ok: false; error: string };

function toResult(error: AuthError | null): AuthResult {
  return error ? { ok: false, error: authErrorMessage(error.code) } : { ok: true };
}

/** Manda un código de un solo uso al mail. Crea el usuario si no existe. */
export async function sendEmailCode(email: string): Promise<AuthResult> {
  const { error } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true },
  });
  return toResult(error);
}

/** Verifica el código; si es correcto, Supabase guarda la sesión y dispara onAuthStateChange. */
export async function verifyEmailCode(email: string, token: string): Promise<AuthResult> {
  const { error } = await supabase.auth.verifyOtp({ email, token, type: 'email' });
  return toResult(error);
}

export async function signOut(): Promise<AuthResult> {
  const { error } = await supabase.auth.signOut();
  return toResult(error);
}

export async function getSession(): Promise<Session | null> {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export function onSessionChange(callback: (session: Session | null) => void): () => void {
  const { data } = supabase.auth.onAuthStateChange((_event, session) => callback(session));
  return () => data.subscription.unsubscribe();
}
