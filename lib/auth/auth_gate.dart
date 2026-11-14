import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../home_page.dart';
import '../login_page.dart';

/// Shows [HomePage] for a signed-in user and [LoginPage] otherwise.
///
/// Listens to auth changes, so signing in through a magic link or signing out
/// switches the page without a reload or manual navigation.
class AuthGate extends StatelessWidget {
  final VoidCallback onToggleTheme;
  final ThemeMode themeMode;

  const AuthGate({
    super.key,
    required this.onToggleTheme,
    required this.themeMode,
  });

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;

    return StreamBuilder<AuthState>(
      stream: auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? auth.currentSession;

        if (session != null) {
          return HomePage(
            // A new key per user resets the page state after re-login.
            key: ValueKey(session.user.id),
            onToggleTheme: onToggleTheme,
            themeMode: themeMode,
          );
        }
        return LoginPage(
          onToggleTheme: onToggleTheme,
          themeMode: themeMode,
        );
      },
    );
  }
}
