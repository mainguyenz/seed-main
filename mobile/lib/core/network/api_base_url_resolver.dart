import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class ApiBaseUrlResolver {
  ApiBaseUrlResolver({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  // Realistic probe timeout for mobile networks (4G/WiFi SSL handshake ~1-3s)
  final Dio _probeClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 3500),
      receiveTimeout: const Duration(milliseconds: 3500),
      sendTimeout: const Duration(milliseconds: 3500),
    ),
  );

  Future<String>? _pending;
  String? _resolved;

  Future<String> resolve() {
    final existing = _resolved;
    if (existing != null) return Future.value(existing);

    return _pending ??= _resolve().whenComplete(() => _pending = null);
  }

  Future<String> _resolve() async {
    // 1. Manually configured URL (via --dart-define=BASE_URL=...)
    if (configuredBaseUrl.isNotEmpty && await _isHealthy(configuredBaseUrl)) {
      return _setResolved(configuredBaseUrl);
    }

    // 2. Previously cached working URL
    final cached = await _storage.read(key: resolvedBaseUrlKey);
    if (cached != null && cached.isNotEmpty && await _isHealthy(cached)) {
      return _setResolved(cached);
    }

    // 3. Primary production cloud backend (Render)
    if (await _isHealthy(renderCloudBaseUrl)) {
      return _setResolved(renderCloudBaseUrl);
    }

    // 4. Secondary fallback cloud backend (Azure)
    if (await _isHealthy(azureCloudBaseUrl)) {
      return _setResolved(azureCloudBaseUrl);
    }

    // 5. Common development targets (Android emulator, Genymotion, localhost)
    final devTarget = await _probeCommonDevHosts();
    if (devTarget != null) {
      return _setResolved(devTarget);
    }

    // 6. Local network discovery (e.g. debugging physical device on office WiFi)
    final discovered = await _discoverOnLocalNetwork();
    if (discovered != null) {
      return _setResolved(discovered);
    }

    // 7. Ultimate fallback: defaultBaseUrl
    return _setResolved(baseUrl, cache: true);
  }

  Future<String> _setResolved(String value, {bool cache = true}) async {
    _resolved = value;
    if (cache) {
      await _storage.write(key: resolvedBaseUrlKey, value: value);
    }
    return value;
  }

  Future<String?> _probeCommonDevHosts() async {
    // 10.0.2.2 is the Android emulator's loopback interface to the host machine
    // 10.0.3.2 is used by Genymotion
    final candidates = <String>[
      'http://10.0.2.2:3000/api',
      'http://10.0.3.2:3000/api',
      'http://127.0.0.1:3000/api',
      'http://localhost:3000/api',
    ];

    for (final candidate in candidates) {
      if (await _isHealthy(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  Future<String?> _discoverOnLocalNetwork() async {
    try {
      final hosts = await _localSubnetHosts();
      const batchSize = 32;

      for (var i = 0; i < hosts.length; i += batchSize) {
        final batch = hosts.skip(i).take(batchSize);
        final probes = await Future.wait(
          batch.map((host) async {
            final candidate = 'http://$host:3000/api';
            return await _isHealthy(candidate) ? candidate : null;
          }),
        );

        for (final candidate in probes) {
          if (candidate != null) return candidate;
        }
      }
    } catch (_) {
      // Ignore network interface enumeration failures on restrictive devices
    }

    return null;
  }

  Future<List<String>> _localSubnetHosts() async {
    final addresses = <String>{};
    final interfaces = await NetworkInterface.list(
      includeLinkLocal: false,
      type: InternetAddressType.IPv4,
    );

    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final parts = address.address.split('.');
        if (parts.length != 4) continue;
        final first = int.tryParse(parts[0]);
        if (first == null || first == 127 || first == 169) continue;

        final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
        for (var host = 1; host <= 254; host++) {
          final candidate = '$prefix.$host';
          if (candidate != address.address) addresses.add(candidate);
        }
      }
    }

    return addresses.toList(growable: false);
  }

  Future<bool> _isHealthy(String apiBaseUrl) async {
    try {
      final uri = Uri.parse(apiBaseUrl);

      // Probe root /health
      final rootHealthUri = uri.replace(path: '/health', query: '');
      try {
        final response = await _probeClient.getUri(rootHealthUri);
        final data = response.data;
        if (response.statusCode == 200 && data is Map && data['success'] == true) {
          return true;
        }
      } catch (_) {}

      // Probe subpath /api/health or /grain/health if root /health didn't respond
      final subPath = '${uri.path}/grain/health'.replaceAll('//', '/');
      final subHealthUri = uri.replace(path: subPath, query: '');
      final response = await _probeClient.getUri(subHealthUri);
      final data = response.data;
      return response.statusCode == 200 &&
          data is Map &&
          data['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
