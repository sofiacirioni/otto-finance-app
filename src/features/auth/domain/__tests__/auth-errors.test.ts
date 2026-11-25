import { authErrorMessage } from '../auth-errors';

describe('authErrorMessage', () => {
  it('traduce códigos conocidos', () => {
    expect(authErrorMessage('otp_expired')).toMatch(/venció/);
  });

  it('usa un mensaje genérico para códigos desconocidos o ausentes', () => {
    expect(authErrorMessage('algo_raro')).toMatch(/No pudimos/);
    expect(authErrorMessage(undefined)).toMatch(/No pudimos/);
  });
});
