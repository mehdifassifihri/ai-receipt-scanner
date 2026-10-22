import 'package:flutter/material.dart';
import '../state/expense_store.dart';
import '../state/account_scope.dart';
import '../widgets/glass_bottom_nav.dart';
import '../widgets/snap_sidebar.dart';
import 'analytics_screen.dart';
import 'ask_snap_screen.dart';
import 'dashboard_screen.dart';
import 'expenses_screen.dart';
import 'receipt_scanner_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _home = 0, _explore = 1, _add = 2, _expenses = 3, _chat = 4;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = _home;
  final _seenExpenseIds = <String>{};
  final _visitedPages = <int>{0};
  List<Widget> get _pages => [
    DashboardScreen(onOpenMenu: () => _scaffoldKey.currentState?.openDrawer()),
    const AnalyticsScreen(),
    const ExpensesScreen(),
    const AskSnapScreen(),
  ];
  int get _page => switch (_index) {
    _explore => 1,
    _expenses => 2,
    _chat => 3,
    _ => 0,
  };

  Iterable<String> _thisMonthIds(ExpenseStore store) {
    final now = DateTime.now();
    return store.expenses
        .where(
          (e) =>
              e.details.date.year == now.year &&
              e.details.date.month == now.month,
        )
        .map((e) => e.id);
  }

  void _onTap(int index, ExpenseStore store) {
    if (index == _add) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ReceiptScannerScreen()),
      );
      return;
    }
    setState(() {
      _index = index;
      _visitedPages.add(_page);
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ExpenseScope.of(context);
    final pages = _pages;
    // Keep marking as seen while the user is on the Expenses tab.
    if (_index == _expenses) _seenExpenseIds.addAll(_thisMonthIds(store));
    final hasUnseen = _thisMonthIds(
      store,
    ).any((id) => !_seenExpenseIds.contains(id));
    return Scaffold(
      key: _scaffoldKey,
      drawerScrimColor: Colors.black.withValues(alpha: .32),
      drawer: SnapSidebar(
        connected: store.connected,
        email: AccountScope.maybeOf(context)?.email,
        onLogout: AccountScope.maybeOf(context)?.signOut,
        onSelect: (index) {
          Navigator.of(context).pop();
          _onTap(index, store);
        },
      ),
      extendBody: true,
      body: IndexedStack(
        index: _page,
        children: [
          for (var i = 0; i < pages.length; i++)
            _visitedPages.contains(i) ? pages[i] : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: GlassBottomNav(
        selectedIndex: _index,
        onTap: (i) => _onTap(i, store),
        destinations: [
          const NavDestination(NavGlyph.home, 'Home'),
          const NavDestination(NavGlyph.explore, 'Analytics'),
          const NavDestination(NavGlyph.add, 'Scan receipt'),
          NavDestination(NavGlyph.heart, 'My expenses', badge: hasUnseen),
          const NavDestination(NavGlyph.chat, 'Ask Snap'),
        ],
      ),
    );
  }
}
