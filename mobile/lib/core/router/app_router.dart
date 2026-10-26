import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/main/screens/main_shell.dart';
import '../../features/auth/providers/auth_provider.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);
  final guestMode = ref.watch(guestModeProvider);

  return GoRouter(
    initialLocation: '/dashboard',
    redirect: (context, state) {
      final isAuthenticated = authState.value ?? false;
      final isGuest = guestMode.value ?? false;
      final hasAccess = isAuthenticated || isGuest;
      final isAuthRoute = state.matchedLocation == '/login' ||
          state.matchedLocation == '/register';

      if (!hasAccess && !isAuthRoute) return '/login';
      if (isAuthenticated && isAuthRoute) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/dashboard',
          builder: (_, __) => const MainShell(initialIndex: 0)),
      GoRoute(
          path: '/storage',
          builder: (_, __) => const MainShell(initialIndex: 1)),
      GoRoute(
          path: '/account',
          builder: (_, __) => const MainShell(initialIndex: 2)),
    ],
  );
});
