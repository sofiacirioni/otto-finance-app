import { useState } from 'react';
import {
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
} from 'react-native';

import { sendEmailCode, verifyEmailCode } from '../data/auth-repository';
import { validateEmail, validateOtpCode } from '../domain/credentials';

type Step = { kind: 'email' } | { kind: 'code'; email: string };

export function SignInScreen() {
  const [step, setStep] = useState<Step>({ kind: 'email' });
  const [emailInput, setEmailInput] = useState('');
  const [codeInput, setCodeInput] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function requestCode() {
    const email = validateEmail(emailInput);
    if (!email.ok) return setError(email.error);
    setBusy(true);
    setError(null);
    const result = await sendEmailCode(email.value);
    setBusy(false);
    if (!result.ok) return setError(result.error);
    setCodeInput('');
    setStep({ kind: 'code', email: email.value });
  }

  async function confirmCode() {
    if (step.kind !== 'code') return;
    const code = validateOtpCode(codeInput);
    if (!code.ok) return setError(code.error);
    setBusy(true);
    setError(null);
    const result = await verifyEmailCode(step.email, code.value);
    setBusy(false);
    // Si salió bien, onAuthStateChange actualiza la sesión y el guard de rutas redirige.
    if (!result.ok) setError(result.error);
  }

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <Text style={styles.title}>Otto</Text>

      {step.kind === 'email' ? (
        <>
          <Text style={styles.label}>Ingresá tu mail y te mandamos un código.</Text>
          <TextInput
            style={styles.input}
            value={emailInput}
            onChangeText={setEmailInput}
            placeholder="vos@mail.com"
            autoCapitalize="none"
            autoComplete="email"
            keyboardType="email-address"
            textContentType="emailAddress"
            editable={!busy}
            onSubmitEditing={requestCode}
          />
          <PrimaryButton label="Enviar código" onPress={requestCode} busy={busy} />
        </>
      ) : (
        <>
          <Text style={styles.label}>Te mandamos un código a {step.email}.</Text>
          <TextInput
            style={styles.input}
            value={codeInput}
            onChangeText={setCodeInput}
            placeholder="123456"
            keyboardType="number-pad"
            autoComplete="one-time-code"
            textContentType="oneTimeCode"
            maxLength={10}
            editable={!busy}
            onSubmitEditing={confirmCode}
          />
          <PrimaryButton label="Entrar" onPress={confirmCode} busy={busy} />
          <Pressable
            disabled={busy}
            onPress={() => {
              setError(null);
              setStep({ kind: 'email' });
            }}
          >
            <Text style={styles.link}>Usar otro mail o pedir otro código</Text>
          </Pressable>
        </>
      )}

      {error && (
        <Text style={styles.error} accessibilityRole="alert">
          {error}
        </Text>
      )}
    </KeyboardAvoidingView>
  );
}

function PrimaryButton({
  label,
  onPress,
  busy,
}: {
  label: string;
  onPress: () => void;
  busy: boolean;
}) {
  return (
    <Pressable
      style={[styles.button, busy && styles.buttonDisabled]}
      onPress={onPress}
      disabled={busy}
      accessibilityRole="button"
    >
      {busy ? <ActivityIndicator color="#fff" /> : <Text style={styles.buttonText}>{label}</Text>}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', padding: 24, gap: 12 },
  title: { fontSize: 48, fontWeight: '600', textAlign: 'center', marginBottom: 24 },
  label: { fontSize: 16 },
  input: {
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 8,
    padding: 12,
    fontSize: 16,
  },
  button: { backgroundColor: '#208AEF', borderRadius: 8, padding: 14, alignItems: 'center' },
  buttonDisabled: { opacity: 0.6 },
  buttonText: { color: '#fff', fontSize: 16, fontWeight: '600' },
  link: { color: '#208AEF', textAlign: 'center', padding: 8 },
  error: { color: '#D93025', textAlign: 'center' },
});
