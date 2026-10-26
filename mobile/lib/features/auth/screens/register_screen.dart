import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../providers/auth_provider.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _showPass = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    final name = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;

    await ref.read(authProvider.notifier).register(name, email, password);
    final state = ref.read(authProvider);
    if (state.hasError && mounted) {
      final language = ref.read(appLanguageProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${appText(language, 'Đăng ký thất bại', 'Registration failed')}: ${localizedText(language, state.error.toString())}',
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFD92D20),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
    } else if (!state.hasError && mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authProvider);
    final isLoading = state.isLoading;
    final language = ref.watch(appLanguageProvider);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: AppTheme.bgDefault),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 36),
                  decoration: BoxDecoration(
                    color: AppTheme.bgPaper,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppTheme.border,
                      width: 1,
                    ),
                    boxShadow: const [],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Organic Sprout Brand Logo
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: const Color(
                                    0x0D2F6B4F), // rgba(47, 107, 79, 0.05)
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppTheme.border,
                                  width: 1,
                                ),
                                boxShadow: const [],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.spa_rounded,
                                  size: 26,
                                  color: Color(0xFF2F6B4F),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Header - Only "Đăng ký" as requested
                        Text(
                          appText(language, 'Đăng ký', 'Sign up'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF1B2C21),
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Name field label
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 8),
                          child: Text(
                            appText(language, 'HỌ VÀ TÊN', 'FULL NAME'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Color(0xFF4D5C52),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        // Name Field
                        TextFormField(
                          controller: _nameCtrl,
                          keyboardType: TextInputType.name,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                              fontSize: 14.5, color: Color(0xFF1B2C21)),
                          decoration: InputDecoration(
                            hintText: appText(
                              language,
                              'Nhập họ và tên của bạn',
                              'Enter your full name',
                            ),
                            hintStyle: const TextStyle(
                                color: Color(0xFF6B7C72), fontSize: 14),
                            prefixIcon: const Icon(Icons.person_outline_rounded,
                                size: 19, color: Color(0xFF6B7C72)),
                            filled: true,
                            fillColor: const Color(0xFFF8FAF8),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2F6B4F), width: 1.5),
                            ),
                            errorStyle:
                                const TextStyle(color: Color(0xFFD92D20)),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().length < 2) {
                              return appText(
                                language,
                                'Họ và tên phải có ít nhất 2 ký tự',
                                'Full name must have at least 2 characters',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Email field label
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 8),
                          child: Text(
                            appText(language, 'ĐỊA CHỈ EMAIL', 'EMAIL ADDRESS'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Color(0xFF4D5C52),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        // Email Field
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          style: const TextStyle(
                              fontSize: 14.5, color: Color(0xFF1B2C21)),
                          decoration: InputDecoration(
                            hintText: 'email@example.com',
                            hintStyle: const TextStyle(
                                color: Color(0xFF6B7C72), fontSize: 14),
                            prefixIcon: const Icon(Icons.email_outlined,
                                size: 19, color: Color(0xFF6B7C72)),
                            filled: true,
                            fillColor: const Color(0xFFF8FAF8),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2F6B4F), width: 1.5),
                            ),
                            errorStyle:
                                const TextStyle(color: Color(0xFFD92D20)),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return appText(
                                language,
                                'Vui lòng nhập địa chỉ email',
                                'Please enter your email address',
                              );
                            }
                            final emailRegex =
                                RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                            if (!emailRegex.hasMatch(value.trim())) {
                              return appText(
                                language,
                                'Định dạng email không hợp lệ',
                                'Invalid email format',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Password field label
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 8),
                          child: Text(
                            appText(language, 'MẬT KHẨU', 'PASSWORD'),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                              color: Color(0xFF4D5C52),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        // Password Field
                        TextFormField(
                          controller: _passCtrl,
                          obscureText: !_showPass,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _register(),
                          style: const TextStyle(
                              fontSize: 14.5, color: Color(0xFF1B2C21)),
                          decoration: InputDecoration(
                            hintText: appText(
                              language,
                              'Nhập mật khẩu của bạn',
                              'Enter your password',
                            ),
                            hintStyle: const TextStyle(
                                color: Color(0xFF6B7C72), fontSize: 14),
                            prefixIcon: const Icon(Icons.lock_outline_rounded,
                                size: 19, color: Color(0xFF6B7C72)),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _showPass
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                                color: const Color(0xFF6B7C72),
                              ),
                              onPressed: () =>
                                  setState(() => _showPass = !_showPass),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAF8),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  const BorderSide(color: AppTheme.border),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                  color: Color(0xFF2F6B4F), width: 1.5),
                            ),
                            errorStyle:
                                const TextStyle(color: Color(0xFFD92D20)),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return appText(
                                language,
                                'Vui lòng nhập mật khẩu',
                                'Please enter your password',
                              );
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 28),

                        // Register button
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _register,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2F6B4F),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: const Color(0x592F6B4F),
                              disabledForegroundColor: const Color(0x8CFFFFFF),
                              shadowColor: const Color(0x332F6B4F),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    appText(language, 'Đăng ký', 'Sign up'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Toggle screen
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: appText(
                                    language,
                                    'Đã có tài khoản? ',
                                    'Already have an account? ',
                                  ),
                                  style: const TextStyle(
                                      color: Color(0xFF6B7C72), fontSize: 13.5),
                                ),
                                TextSpan(
                                  text: appText(
                                      language, 'Đăng nhập ngay', 'Log in now'),
                                  style: const TextStyle(
                                    color: Color(0xFF2F6B4F),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
