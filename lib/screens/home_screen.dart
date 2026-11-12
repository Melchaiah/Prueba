import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/memory_repository.dart';
import '../widgets/common.dart';
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

  static const _tabs = [
    ('Resumen', Icons.pie_chart_outline, Icons.pie_chart),
    ('Movimientos', Icons.receipt_long_outlined, Icons.receipt_long),
    ('Planificación', Icons.event_repeat_outlined, Icons.event_repeat),
    ('Ajustes', Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final scope = RepoScope.of(context);
    final repo = scope.repo;
    // En tablets y pantallas anchas la navegación va al costado.
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = ContentWidth(
      child: switch (_tab) {
        0 => const SummaryTab(),
        1 => const MovementsTab(),
        2 => const PlanningTab(),
        _ => const SettingsTab(),
      },
    );
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_tabs[_tab].$1),
          if (s.household != null && (scope.user?.households.length ?? 1) > 1)
            Text(s.household!.name, style: Theme.of(context).textTheme.labelMedium),
        ]),
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
        child: wide
            ? Row(children: [
                NavigationRail(
                  selectedIndex: _tab,
                  onDestinationSelected: (i) => setState(() => _tab = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final (label, icon, selected) in _tabs)
                      NavigationRailDestination(
                          icon: Icon(icon), selectedIcon: Icon(selected), label: Text(label)),
                  ],
                ),
                Expanded(child: body),
              ])
            : body,
      ),
      floatingActionButton: _tab < 2
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Gasto'),
              tooltip: 'Cargar un gasto',
              onPressed: () => openExpenseForm(context),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [
                for (final (label, icon, selected) in _tabs)
                  NavigationDestination(
                      icon: Icon(icon), selectedIcon: Icon(selected), label: label),
              ],
            ),
    );
  }
}
