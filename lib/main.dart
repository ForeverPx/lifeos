import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'checkin/checkin_screen.dart';
import 'collect/collect_screen.dart';
import 'diary/diary_screen.dart';
import 'home/home_dashboard.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('zh_CN');
  runApp(const LifeOSApp());
}

class LifeOSApp extends StatelessWidget {
  const LifeOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6B5344),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    );
    return MaterialApp(
      title: 'LifeOS',
      theme: base.copyWith(
        textTheme: GoogleFonts.notoSansScTextTheme(base.textTheme),
        appBarTheme: AppBarTheme(
          centerTitle: false,
          titleTextStyle: GoogleFonts.newsreader(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: base.colorScheme.onSurface,
          ),
        ),
      ),
      home: const HomeShell(),
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
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeDashboard(onOpenTab: (i) => setState(() => _index = i)),
          const DiaryScreen(),
          const CollectScreen(),
          const CheckinScreen(),
        ],
      ),
      bottomNavigationBar: MediaQuery.textScalerOf(context).scale(1) > 1.15
          ? _buildNavBar(cs)
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                height: 56,
                labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
              ),
              child: _buildNavBar(cs),
            ),
    );
  }

  Widget _buildNavBar(ColorScheme cs) {
    return NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: [
        NavigationDestination(
          icon: Icon(Icons.home_outlined, color: cs.onSurfaceVariant),
          selectedIcon: Icon(Icons.home_rounded, color: cs.primary),
          label: '首页',
        ),
        NavigationDestination(
          icon: Icon(Icons.book_outlined, color: cs.onSurfaceVariant),
          selectedIcon: Icon(Icons.auto_stories_rounded, color: cs.primary),
          label: '日记',
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_outline, color: cs.onSurfaceVariant),
          selectedIcon: Icon(Icons.bookmark_rounded, color: cs.primary),
          label: '收藏',
        ),
        NavigationDestination(
          icon: Icon(Icons.task_alt_outlined, color: cs.onSurfaceVariant),
          selectedIcon: Icon(Icons.task_alt_rounded, color: cs.primary),
          label: '打卡',
        ),
      ],
    );
  }
}
