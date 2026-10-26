import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/connectivity_sync_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/update/mobile_update_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ConnectivitySyncService().init();
  runApp(
    const ProviderScope(
      child: SeedApp(),
    ),
  );
}

class SeedApp extends ConsumerWidget {
  const SeedApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'SeedVision',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.appTheme,
      routerConfig: router,
      builder: (context, child) {
        return MobileUpdateGate(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
