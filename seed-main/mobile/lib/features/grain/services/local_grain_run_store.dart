import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LocalGrainRunStore {
  static const _fileName = 'pending_grain_runs.json';

  Future<List<Map<String, dynamic>>> readAll() async {
    final file = await _file();
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(Map<String, dynamic> run) async {
    final runs = await readAll();
    runs.insert(0, run);
    await _write(runs);
  }

  Future<void> updateResult(String runId, Map<String, dynamic> result) async {
    final runs = await readAll();
    var changed = false;
    for (final item in runs) {
      final rawResult = item['result'];
      if (rawResult is! Map) continue;
      final run = rawResult['run'];
      final storedRunId = run is Map ? run['id']?.toString() ?? '' : '';
      final clientRunId = item['clientRunId']?.toString() ?? '';
      if (storedRunId == runId || clientRunId == runId) {
        item['result'] = result;
        item['updatedAt'] = DateTime.now().toIso8601String();
        item['pendingSync'] = true;
        changed = true;
      }
    }
    if (changed) await _write(runs);
  }

  Future<List<Map<String, dynamic>>> readVisible({
    required bool isGuest,
    String? userId,
  }) async {
    final runs = await readAll();
    return runs.where((run) {
      final ownerId = _ownerId(run);
      return isGuest ? ownerId == null : userId != null && ownerId == userId;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> claimAndReadPendingForSync(
      String userId) async {
    final runs = await readAll();
    var changed = false;
    for (final run in runs) {
      if (_needsSync(run) && _ownerId(run) == null) {
        run['ownerUserId'] = userId;
        changed = true;
      }
    }
    if (changed) await _write(runs);
    return runs
        .where((run) => _needsSync(run) && _ownerId(run) == userId)
        .toList();
  }

  Future<void> removePendingForSync(String userId) async {
    final runs = await readAll();
    await _write(runs
        .where((run) => !(_needsSync(run) && _ownerId(run) == userId))
        .toList());
  }

  Future<void> clear() => _write([]);

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<void> _write(List<Map<String, dynamic>> runs) async {
    final file = await _file();
    final compacted = runs.map(_compactRunForStorage).toList();
    await file.writeAsString(jsonEncode(compacted), flush: true);
  }

  Map<String, dynamic> _compactRunForStorage(Map<String, dynamic> item) {
    final next = Map<String, dynamic>.from(item);
    final rawResult = next['result'];
    if (rawResult is Map) {
      final result = Map<String, dynamic>.from(rawResult);
      final samMask = result['sam_mask_png_base64']?.toString() ?? '';
      final mask = result['mask_png_base64']?.toString() ?? '';
      if (samMask.isNotEmpty && samMask == mask) {
        result['sam_mask_png_base64'] = '';
      }
      next['result'] = result;
    }
    return next;
  }

  bool _needsSync(Map<String, dynamic> item) {
    if (item['pendingSync'] == true) return true;
    if (item['pendingSync'] == false) return false;
    final result = item['result'];
    if (result is! Map) return false;
    final run = result['run'];
    if (run is! Map) return false;
    return run['localOnly'] == true ||
        run['offline'] == true ||
        run['id']?.toString().startsWith('local-') == true;
  }

  String? _ownerId(Map<String, dynamic> item) {
    final value = item['ownerUserId']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }
}
