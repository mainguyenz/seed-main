import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_language.dart';
import '../theme/app_theme.dart';
import 'mobile_update_service.dart';

class MobileUpdateGate extends ConsumerStatefulWidget {
  final Widget child;

  const MobileUpdateGate({super.key, required this.child});

  @override
  ConsumerState<MobileUpdateGate> createState() => _MobileUpdateGateState();
}

class _MobileUpdateGateState extends ConsumerState<MobileUpdateGate> {
  static const _channel = MethodChannel('vn.mekonglab.seedvision/app_update');

  final _updateService = MobileUpdateService();
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    try {
      final result = await _updateService.check();
      if (!mounted || result == null) return;
      await _showUpdateDialog(result);
    } catch (_) {}
  }

  Future<void> _showUpdateDialog(MobileUpdateCheckResult result) async {
    final info = result.updateInfo;
    final required = result.isRequired;
    final language = ref.read(appLanguageProvider);
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (context) {
        return PopScope(
          canPop: !required,
          child: AlertDialog(
            title: Text(localizedText(language, info.title)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(localizedText(language, info.message)),
                const SizedBox(height: 10),
                Text(
                  '${appText(language, 'Phiên bản mới', 'New version')}: ${info.latestVersionName}',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            actions: [
              if (!required)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(appText(language, 'Để sau', 'Later')),
                ),
              ElevatedButton.icon(
                onPressed: () => _openStore(info.playStoreUrl),
                icon: const Icon(Icons.open_in_new),
                label: Text(appText(language, 'Cập nhật', 'Update')),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openStore(String playStoreUrl) async {
    await _channel.invokeMethod<void>('openStore', {
      'playStoreUrl': playStoreUrl,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
