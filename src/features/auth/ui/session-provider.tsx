import type { Session } from '@supabase/supabase-js';
import { createContext, use, useEffect, useState, type PropsWithChildren } from 'react';

import { getSession, onSessionChange, signOut } from '../data/auth-repository';

type SessionContextValue = {
  session: Session | null;
  isLoading: boolean;
  signOut: typeof signOut;
};

const SessionContext = createContext<SessionContextValue | null>(null);

export function useSession(): SessionContextValue {
  const value = use(SessionContext);
  if (!value) throw new Error('useSession debe usarse dentro de <SessionProvider />');
  return value;
}

export function SessionProvider({ children }: PropsWithChildren) {
  const [session, setSession] = useState<Session | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    let active = true;
    getSession()
      .then((s) => {
        if (active) setSession(s);
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    const unsubscribe = onSessionChange((s) => setSession(s));
    return () => {
      active = false;
      unsubscribe();
    };
  }, []);

  return <SessionContext value={{ session, isLoading, signOut }}>{children}</SessionContext>;
}
