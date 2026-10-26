import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/i18n/app_language.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/auth_provider.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _api = ApiClient();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _guestMode = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      const storage = FlutterSecureStorage();
      if (await storage.read(key: guestModeKey) == 'true') {
        if (mounted) {
          setState(() {
            _guestMode = true;
            _loading = false;
          });
        }
        return;
      }
      final response = await _api.get('/users/me');
      final user = Map<String, dynamic>.from(response.data['data'] as Map);
      _nameCtrl.text = user['name']?.toString() ?? '';
      _emailCtrl.text = user['email']?.toString() ?? '';
      _roleCtrl.text = user['role']?.toString() ?? 'user';
    } catch (error) {
      final language = ref.read(appLanguageProvider);
      _showError(
        '${appText(language, 'Không tải được tài khoản', 'Could not load account')}: $error',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (_nameCtrl.text.trim().length < 2) {
      final language = ref.read(appLanguageProvider);
      _showError(appText(
        language,
        'Họ và tên cần ít nhất 2 ký tự',
        'Full name needs at least 2 characters',
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await _api.patch('/users/me', data: {
        'name': _nameCtrl.text.trim(),
      });
      final user = Map<String, dynamic>.from(response.data['data'] as Map);
      _nameCtrl.text = user['name']?.toString() ?? _nameCtrl.text;
      if (mounted) {
        final language = ref.read(appLanguageProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(appText(
              language,
              'Đã cập nhật tài khoản',
              'Account updated',
            )),
          ),
        );
      }
    } catch (error) {
      final language = ref.read(appLanguageProvider);
      _showError(
        '${appText(language, 'Cập nhật thất bại', 'Update failed')}: $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout();
    if (mounted) context.go('/login');
  }

  void _openSettings(BuildContext context) {
    final language = ref.read(appLanguageProvider);
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(appText(language, 'Cài đặt', 'Settings')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appText(
                language,
                'Đơn vị đo mặc định',
                'Default measurement unit',
              )),
              subtitle: Text(appText(
                language,
                'Milimét (mm)',
                'Millimeter (mm)',
              )),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appText(
                language,
                'Tự động lưu kết quả',
                'Automatically save results',
              )),
              subtitle: Text(appText(language, 'Đang bật', 'Enabled')),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(appText(language, 'Ngôn ngữ', 'Language')),
              subtitle: Text(language.label),
              trailing: DropdownButton<AppLanguage>(
                value: language,
                onChanged: (nextLanguage) {
                  if (nextLanguage == null) return;
                  ref
                      .read(appLanguageProvider.notifier)
                      .setLanguage(nextLanguage);
                  Navigator.of(context).pop();
                },
                items: AppLanguage.values
                    .map(
                      (item) => DropdownMenuItem<AppLanguage>(
                        value: item,
                        child: Text(item.label),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(appText(language, 'Đóng', 'Close')),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    final language = ref.read(appLanguageProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(localizedText(language, message)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_guestMode) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            appText(language, 'Chế độ không đăng nhập', 'Guest mode'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            appText(
              language,
              'Các bản xử lý đang được lưu trên điện thoại này. Đăng nhập hoặc đăng ký để đồng bộ chúng lên tài khoản của bạn.',
              'Your analyses are saved on this phone. Log in or sign up to sync them to your account.',
            ),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => context.go('/login'),
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                  appText(language, 'Đăng nhập để đồng bộ', 'Log in to sync')),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () => context.go('/register'),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                  appText(language, 'Đăng ký tài khoản', 'Create account')),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          appText(language, 'Thông tin tài khoản', 'Account information'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          appText(
            language,
            'Thông tin tài khoản được dùng chung cho web và mobile.',
            'Account information is shared between web and mobile.',
          ),
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: appText(language, 'Họ và tên', 'Full name'),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _emailCtrl,
          enabled: false,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _roleCtrl,
          enabled: false,
          decoration: InputDecoration(
            labelText: appText(language, 'Vai trò', 'Role'),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _saving ? null : _saveProfile,
          child: _saving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(appText(language, 'Lưu thay đổi', 'Save changes')),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: () => _openSettings(context),
          child: Text(appText(language, 'Cài đặt', 'Settings')),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout),
          label: Text(appText(language, 'Đăng xuất', 'Log out')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red.shade700,
            side: BorderSide(color: Colors.red.shade200),
          ),
        ),
      ],
    );
  }
}
