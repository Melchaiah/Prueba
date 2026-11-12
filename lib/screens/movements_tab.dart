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

    // Gastos fijos marcados como "este mes no se paga".
    final skipped = s.recurring
        .where((r) => r.activeIn(s.month) && r.amountIn(s.month) <= 0)
        .toList();

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
                if (charges.isEmpty && incomes.isEmpty && settlements.isEmpty && skipped.isEmpty)
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
                if (skipped.isNotEmpty) ...[
                  const SectionHeader('Fijos que este mes no se pagan', dense: true),
                  for (final r in skipped)
                    ListTile(
                      leading: CategoryAvatar(r.category, personal: !r.isShared),
                      title: Text(r.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          'Habitual: ${formatMoney(r.amount, r.currency, compact: true)}'),
                      trailing: const Icon(Icons.money_off),
                      onTap: () => _recurringOptions(context, r, s.month),
                    ),
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
      if (c.recurring) c.adjusted ? 'Fijo mensual · ajustado' : 'Fijo mensual',
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
      onTap: () => e is RecurringExpense
          ? _recurringOptions(context, e, c.month)
          : openExpenseForm(context, existing: e),
    );
  }
}

/// Opciones al tocar un gasto fijo: ajustar solo este mes o editarlo entero.
void _recurringOptions(BuildContext context, RecurringExpense r, YearMonth month) {
  final s = HouseholdScope.of(context);
  if (!r.isShared && r.paidBy != s.me) {
    openExpenseForm(context, existing: r); // muestra el aviso de solo lectura
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text('Ajustar solo ${monthLabel(month)}'),
          subtitle: const Text('Si este mes el monto es distinto o no se paga'),
          onTap: () {
            Navigator.pop(sheet);
            showMonthAdjustDialog(context, r, month);
          },
        ),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('Editar el gasto fijo'),
          subtitle: const Text('Cambia todos los meses'),
          onTap: () {
            Navigator.pop(sheet);
            openExpenseForm(context, existing: r);
          },
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
}
