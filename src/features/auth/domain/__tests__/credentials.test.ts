import { validateEmail, validateOtpCode } from '../credentials';

describe('validateEmail', () => {
  it('normaliza espacios y mayúsculas', () => {
    expect(validateEmail('  Ana@Mail.COM ')).toEqual({ ok: true, value: 'ana@mail.com' });
  });

  it.each(['', 'ana', 'ana@', '@mail.com', 'ana mail.com'])('rechaza %p', (input) => {
    expect(validateEmail(input)).toEqual({ ok: false, error: 'Ingresá un mail válido.' });
  });
});

describe('validateOtpCode', () => {
  it.each(['123456', ' 123456 ', '1234567890'])('acepta %p', (input) => {
    expect(validateOtpCode(input)).toEqual({ ok: true, value: input.trim() });
  });

  it.each(['', '12345', '12345678901', '12a456', '123 456'])('rechaza %p', (input) => {
    expect(validateOtpCode(input).ok).toBe(false);
  });
});
