import { Pressable, StyleSheet, Text, View } from 'react-native';

import { useSession } from '@/features/auth';

export default function HomeScreen() {
  const { session, signOut } = useSession();

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Otto</Text>
      <Text>{session?.user.email}</Text>
      <Pressable onPress={signOut} accessibilityRole="button">
        <Text style={styles.link}>Cerrar sesión</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    gap: 12,
  },
  title: {
    fontSize: 48,
    fontWeight: '600',
  },
  link: { color: '#208AEF', padding: 8 },
});
