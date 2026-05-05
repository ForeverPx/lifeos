import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'checkin/checkin_screen.dart';
import 'collect/collect_screen.dart';
import 'config/github_repo_prefs.dart';
import 'config/theme_prefs.dart';
import 'diary/diary_screen.dart';
import 'home/home_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  await ThemePrefs.load();
  await GitHubRepoPrefs.load();
  runApp(const LifeOSApp());
}

bool _useTouchForuiTheme() {
  return const <TargetPlatform>{
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.fuchsia,
  }.contains(defaultTargetPlatform);
}

FThemeData _lifeosForuiTheme({required bool light}) {
  final touch = _useTouchForuiTheme();
  if (light) {
    return touch ? FThemes.blue.light.touch : FThemes.blue.light.desktop;
  }
  return touch ? FThemes.neutral.dark.touch : FThemes.neutral.dark.desktop;
}

class LifeOSApp extends StatelessWidget {
  const LifeOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemePrefs.notifier,
      builder: (context, pref, _) {
        final fLight = _lifeosForuiTheme(light: true);
        final fDark = _lifeosForuiTheme(light: false);
        return MaterialApp(
          title: 'LifeOS',
          theme: fLight.toApproximateMaterialTheme().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF5F7FA),
            colorScheme: fLight.toApproximateMaterialTheme().colorScheme.copyWith(
              surface: const Color(0xFFF5F7FA),
            ),
          ),
          darkTheme: fDark.toApproximateMaterialTheme(),
          themeMode: pref.themeMode,
          locale: const Locale('zh', 'CN'),
          supportedLocales: FLocalizations.supportedLocales,
          localizationsDelegates: FLocalizations.localizationsDelegates,
          builder: (ctx, child) {
            final brightness = Theme.of(ctx).brightness;
            final fTheme = brightness == Brightness.dark ? fDark : fLight;
            return FTheme(
              data: fTheme,
              child: FToaster(
                child: FTooltipGroup(child: child ?? const SizedBox.shrink()),
              ),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _tabs = [
    _NavItem(icon: Icons.home_rounded, label: '首页'),
    _NavItem(icon: Icons.calendar_month_rounded, label: '日记'),
    _NavItem(icon: Icons.bookmark_rounded, label: '收藏'),
    _NavItem(icon: Icons.fact_check_rounded, label: '打卡'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? colors.background : Colors.white;
    final selectedColor = colors.primary;
    final unselectedColor = colors.mutedForeground;

    return Scaffold(
      backgroundColor: isDark ? colors.background : const Color(0xFFF5F7FA),
      body: IndexedStack(
        index: _index,
        children: [
          HomeDashboard(onOpenTab: (i) => setState(() => _index = i)),
          const DiaryScreen(),
          const CollectScreen(),
          const CheckinScreen(),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final selected = _index == i;
                return GestureDetector(
                  onTap: () => setState(() => _index = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? selectedColor.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tab.icon,
                          size: 22,
                          color: selected ? selectedColor : unselectedColor,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? selectedColor : unselectedColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
