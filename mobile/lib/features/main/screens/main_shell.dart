import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_language.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/screens/account_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../storage/screens/storage_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShell({super.key, required this.initialIndex});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialIndex != widget.initialIndex) {
      _currentIndex = widget.initialIndex;
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(appLanguageProvider);
    final titles = [
      appText(language, 'Trang chủ', 'Home'),
      appText(language, 'Lưu trữ', 'Storage'),
      appText(language, 'Tài khoản', 'Account'),
    ];
    const pages = [
      DashboardScreen(),
      StorageScreen(),
      AccountScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: _ShellTopBar(
          title: titles[_currentIndex],
          language: language,
          onLanguageChanged: (nextLanguage) =>
              ref.read(appLanguageProvider.notifier).setLanguage(nextLanguage),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: appText(language, 'Trang chủ', 'Home'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.inventory_2_outlined),
            activeIcon: const Icon(Icons.inventory_2),
            label: appText(language, 'Lưu trữ', 'Storage'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.account_circle_outlined),
            activeIcon: const Icon(Icons.account_circle),
            label: appText(language, 'Tài khoản', 'Account'),
          ),
        ],
      ),
    );
  }
}

class _ShellTopBar extends StatelessWidget {
  final String title;
  final AppLanguage language;
  final ValueChanged<AppLanguage> onLanguageChanged;

  const _ShellTopBar({
    required this.title,
    required this.language,
    required this.onLanguageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).appBarTheme.titleTextStyle ??
        Theme.of(context).textTheme.titleLarge;

    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          height: kToolbarHeight,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 88),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: titleStyle,
                ),
              ),
              Positioned(
                right: 8,
                child: _LanguageToggle(
                  language: language,
                  onChanged: onLanguageChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  final AppLanguage language;
  final ValueChanged<AppLanguage> onChanged;

  const _LanguageToggle({
    required this.language,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final nextLanguage =
        language == AppLanguage.vi ? AppLanguage.en : AppLanguage.vi;

    return Semantics(
      button: true,
      label: appText(language, 'Đổi ngôn ngữ', 'Switch language'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => onChanged(nextLanguage),
          child: Container(
            height: 32,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppTheme.border),
              color: Colors.white,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LanguageToggleOption(
                  label: 'VI',
                  active: language == AppLanguage.vi,
                ),
                _LanguageToggleOption(
                  label: 'EN',
                  active: language == AppLanguage.en,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageToggleOption extends StatelessWidget {
  final String label;
  final bool active;

  const _LanguageToggleOption({
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 30,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? Colors.white : AppTheme.primary,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
