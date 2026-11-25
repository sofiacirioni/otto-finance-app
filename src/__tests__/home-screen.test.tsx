import { fireEvent, render } from '@testing-library/react-native';

import HomeScreen from '../app/(app)/index';

const mockSignOut = jest.fn();

jest.mock('@/features/auth', () => ({
  useSession: () => ({
    session: { user: { email: 'ana@mail.com' } },
    isLoading: false,
    signOut: mockSignOut,
  }),
}));

describe('HomeScreen', () => {
  it('muestra el nombre de la app y el mail del usuario', async () => {
    const { getByText } = await render(<HomeScreen />);
    expect(getByText('Otto')).toBeTruthy();
    expect(getByText('ana@mail.com')).toBeTruthy();
  });

  it('cierra sesión', async () => {
    const { getByText } = await render(<HomeScreen />);
    fireEvent.press(getByText('Cerrar sesión'));
    expect(mockSignOut).toHaveBeenCalled();
  });
});
