import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/money.dart';

class MonthSelector extends StatelessWidget {
  const MonthSelector({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Mes anterior',
          onPressed: () => s.setMonth(s.month.add(-1)),
        ),
        SizedBox(
          width: 160,
          child: Text(monthLabel(s.month),
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Mes siguiente',
          onPressed: () => s.setMonth(s.month.add(1)),
        ),
      ],
    );
  }
}
