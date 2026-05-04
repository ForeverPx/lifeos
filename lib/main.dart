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
    // Blue accent for light mode; dark mode stays neutral gray.
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
          theme: fLight.toApproximateMaterialTheme(),
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

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colors;
    return FScaffold(
      scaffoldStyle: FScaffoldStyleDelta.delta(
        footerDecoration: DecorationDelta.value(const BoxDecoration()),
      ),
      childPad: false,
      footer: FBottomNavigationBar(
        index: _index,
        onChange: (i) => setState(() => _index = i),
        safeAreaBottom: true,
        style: FBottomNavigationBarStyleDelta.delta(
          decoration: DecorationDelta.value(BoxDecoration(color: colors.background)),
        ),
        children: [
          FBottomNavigationBarItem(
            icon: Icon(FIcons.house),
            label: Text('首页'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(FIcons.bookOpenText),
            label: Text('日记'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(FIcons.bookmark),
            label: Text('收藏'),
          ),
          FBottomNavigationBarItem(
            icon: Icon(FIcons.listTodo),
            label: Text('打卡'),
          ),
        ],
      ),
      child: IndexedStack(
        index: _index,
        children: [
          HomeDashboard(onOpenTab: (i) => setState(() => _index = i)),
          const DiaryScreen(),
          const CollectScreen(),
          const CheckinScreen(),
        ],
      ),
    );
  }
}
