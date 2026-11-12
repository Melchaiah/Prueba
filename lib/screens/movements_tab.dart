import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'dialogs.dart';
import 'expense_form_screen.dart';

class MovementsTab extends StatelessWidget {
  const MovementsTab({super.key});

  int _day(Charge c) => switch (c.source) {
        Expense e => c.installment == 1 ? e.date.day : 1,
        RecurringExpense r => r.dayOfMonth,
        _ => 1,
      };

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final t = Theme.of(context).textTheme;
    final charges = s.monthCharges..sort((a, b) => _day(b).compareTo(_day(a)));
    final incomes = s.incomes.where((i) => i.month == s.month).toList();
    final settlements = s.settlements
        .where((x) => YearMonth.fromDate(x.date) == s.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    // Gastos agrupados por día, del más reciente al más viejo.
    final byDay = <int, List<Charge>>{};
    for (final c in charges) {
      byDay.putIfAbsent(_day(c), () => []).add(c);
    }

    return Column(
      children: [
        const MonthHeader(),
        Expanded(
          child: MonthSwiper(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (charges.isEmpty && incomes.isEmpty && settlements.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 56, color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('No hay movimientos este mes', style: t.titleMedium),
                      const SizedBox(height: 4),
                      Text('Tocá "Gasto" para cargar el primero.',
                          style: t.bodyMedium, textAlign: TextAlign.center),
                    ]),
                  ),
                for (final day in byDay.keys) ...[
                  SectionHeader('$day de ${monthLabel(s.month).split(' ').first.toLowerCase()}',
                      dense: true),
                  for (final c in byDay[day]!) _ChargeTile(c),
                ],
                if (incomes.isNotEmpty) ...[
                  const SectionHeader('Ingresos'),
                  for (final i in incomes)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                        child: const Icon(Icons.payments_outlined, size: 22),
                      ),
                      title: Text(i.description),
                      subtitle: Text(s.nameOf(i.memberId)),
                      trailing: TrailingAmount('+ ${formatMoney(i.amount, i.currency)}'),
                      onTap: () => showIncomeDialog(context, existing: i),
                    ),
                ],
                if (settlements.isNotEmpty) ...[
                  const SectionHeader('Pagos entre ustedes'),
                  for (final x in settlements)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                        foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
                        child: const Icon(Icons.handshake_outlined, size: 22),
                      ),
                      title: Text('${s.nameOf(x.from)} le pagó a ${s.nameOf(x.to)}'),
                      subtitle: Text(formatDate(x.date)),
                      trailing: TrailingAmount(formatMoney(x.amount, x.currency)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ChargeTile extends StatelessWidget {
  const _ChargeTile(this.c);
  final Charge c;

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final e = c.source;
    final tags = <String>[
      'Pagó ${s.nameOf(e.paidBy)}',
      if (!e.isShared) 'Personal',
      if (!e.isShared && e.paidBy == s.me && !isPublic(e, s.household?.member(s.me))) 'Privado',
      if (c.totalInstallments > 1) 'Cuota ${c.installment}/${c.totalInstallments}',
      if (c.recurring) 'Fijo mensual',
    ];
    final myShare = e.isShared ? shareAmounts(c.amount, e.split)[s.me] : null;
    return ListTile(
      leading: CategoryAvatar(e.category, personal: !e.isShared),
      title: Text(e.description, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(tags.join(' · ')),
      trailing: TrailingAmount(
        formatMoney(c.amount, c.currency),
        detail: myShare == null ? null : 'te toca ${formatMoney(myShare, c.currency, compact: true)}',
      ),
      onTap: () => openExpenseForm(context, existing: e),
    );
  }
}
