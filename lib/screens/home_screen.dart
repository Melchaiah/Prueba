import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/memory_repository.dart';
import 'expense_form_screen.dart';
import 'movements_tab.dart';
import 'planning_tab.dart';
import 'settings_tab.dart';
import 'summary_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  static const _titles = ['Resumen', 'Movimientos', 'Planificación', 'Ajustes'];

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final scope = RepoScope.of(context);
    final repo = scope.repo;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          if (scope.demo && repo is MemoryRepository && s.partner != null)
            TextButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: Text('Ver como ${s.partner!.name}'),
              onPressed: repo.switchToPartner,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_tab) {
          0 => const SummaryTab(),
          1 => const MovementsTab(),
          2 => const PlanningTab(),
          _ => const SettingsTab(),
        },
      ),
      floatingActionButton: _tab < 2
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
              onPressed: () => openExpenseForm(context),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Resumen'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimientos'),
          NavigationDestination(icon: Icon(Icons.event_repeat_outlined), selectedIcon: Icon(Icons.event_repeat), label: 'Planificación'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}
