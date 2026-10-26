import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../../features/grain/services/grain_analysis_api.dart';

/// Watches device connectivity and automatically syncs pending local grain
/// analysis runs when the network comes back online.
class ConnectivitySyncService {
  static final ConnectivitySyncService _instance =
      ConnectivitySyncService._internal();
  factory ConnectivitySyncService() => _instance;
  ConnectivitySyncService._internal();

  final _connectivity = Connectivity();
  final _storage = const FlutterSecureStorage();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _wasOffline = false;
  bool _syncing = false;

  /// Call once at app startup (e.g. in main.dart).
  void init() {
    _subscription?.cancel();
    _subscription = _connectivity.onConnectivityChanged.listen(_onChanged);
    // Check current state so we know whether the very first transition
    // should be treated as "coming back online".
    _connectivity.checkConnectivity().then((results) {
      _wasOffline = results.every((r) => r == ConnectivityResult.none);
    });
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onChanged(List<ConnectivityResult> results) async {
    final isOffline = results.every((r) => r == ConnectivityResult.none);

    if (_wasOffline && !isOffline) {
      // Just came back online → attempt sync.
      await _trySync();
    }

    _wasOffline = isOffline;
  }

  Future<void> _trySync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      // Guest users don't have server-side auth, skip sync.
      final isGuest = await _storage.read(key: guestModeKey) == 'true';
      if (isGuest) return;

      // Only sync if we have auth tokens.
      final accessToken = await _storage.read(key: accessTokenKey);
      final refreshToken = await _storage.read(key: refreshTokenKey);
      if (accessToken == null && refreshToken == null) return;

      await GrainAnalysisApi().syncPendingRuns();
    } catch (_) {
      // Sync failed (maybe network is still flaky). Will retry on the next
      // connectivity change or when the user triggers an explicit action.
    } finally {
      _syncing = false;
    }
  }
}
