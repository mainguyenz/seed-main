import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';

class ApiBaseUrlResolver {
  ApiBaseUrlResolver({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;
  final Dio _probeClient = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 700),
      receiveTimeout: const Duration(milliseconds: 700),
      sendTimeout: const Duration(milliseconds: 700),
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
    if (configuredBaseUrl.isNotEmpty && await _isHealthy(configuredBaseUrl)) {
      return _setResolved(configuredBaseUrl);
    }

    final cached = await _storage.read(key: resolvedBaseUrlKey);
    if (cached != null && await _isHealthy(cached)) {
      return _setResolved(cached);
    }

    if (await _isHealthy(defaultBaseUrl)) {
      return _setResolved(defaultBaseUrl);
    }

    final discovered = await _discoverOnLocalNetwork();
    if (discovered != null) return _setResolved(discovered);

    return _setResolved(baseUrl, cache: false);
  }

  Future<String> _setResolved(String value, {bool cache = true}) async {
    _resolved = value;
    if (cache) {
      await _storage.write(key: resolvedBaseUrlKey, value: value);
    }
    return value;
  }

  Future<String?> _discoverOnLocalNetwork() async {
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
      final healthUri = uri.replace(path: '/health', query: '');
      final response = await _probeClient.getUri(healthUri);
      final data = response.data;
      return response.statusCode == 200 &&
          data is Map &&
          data['success'] == true;
    } catch (_) {
      return false;
    }
  }
}
