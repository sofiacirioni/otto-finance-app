import { render } from '@testing-library/react-native';

import HomeScreen from '../app/index';

describe('HomeScreen', () => {
  it('renders the app name', async () => {
    const { getByText } = await render(<HomeScreen />);
    expect(getByText('Otto')).toBeTruthy();
  });
});
