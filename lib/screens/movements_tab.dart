import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/month_selector.dart';
import 'dialogs.dart';
import 'expense_form_screen.dart';

IconData categoryIcon(String c) => switch (c) {
      'Supermercado' => Icons.shopping_cart,
      'Alquiler / Expensas' => Icons.home,
      'Servicios' => Icons.bolt,
      'Transporte' => Icons.directions_bus,
      'Salidas' => Icons.restaurant,
      'Salud' => Icons.local_hospital,
      'Ropa' => Icons.checkroom,
      'Hogar' => Icons.chair,
      'Suscripciones' => Icons.subscriptions,
      'Educación' => Icons.school,
      'Regalos' => Icons.card_giftcard,
      _ => Icons.receipt,
    };

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
    final charges = s.monthCharges..sort((a, b) => _day(b).compareTo(_day(a)));
    final incomes = s.incomes.where((i) => i.month == s.month).toList();
    final settlements = s.settlements
        .where((x) => YearMonth.fromDate(x.date) == s.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        const MonthSelector(),
        if (charges.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No hay gastos este mes. Tocá "+ Gasto" para cargar el primero.',
                textAlign: TextAlign.center),
          ),
        for (final c in charges) _ChargeTile(c),
        if (incomes.isNotEmpty) ...[
          const _Header('Ingresos'),
          for (final i in incomes)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.payments)),
              title: Text(i.description),
              subtitle: Text(s.nameOf(i.memberId)),
              trailing: Text('+ ${formatMoney(i.amount, i.currency)}',
                  style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              onTap: () => showIncomeDialog(context, existing: i),
            ),
        ],
        if (settlements.isNotEmpty) ...[
          const _Header('Pagos entre ustedes'),
          for (final x in settlements)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.handshake)),
              title: Text('${s.nameOf(x.from)} → ${s.nameOf(x.to)}'),
              subtitle: Text(formatDate(x.date)),
              trailing: Text(formatMoney(x.amount, x.currency)),
            ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );
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
      if (!e.isShared && !e.visibleToPartner && e.paidBy == s.me) '🔒 Privado',
      if (c.totalInstallments > 1) 'Cuota ${c.installment}/${c.totalInstallments}',
      if (c.recurring) 'Fijo mensual',
    ];
    final myShare = e.isShared ? shareAmounts(c.amount, e.split)[s.me] : null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: e.isShared ? scheme.primaryContainer : scheme.tertiaryContainer,
        child: Icon(categoryIcon(e.category), size: 20),
      ),
      title: Text(e.description),
      subtitle: Text(tags.join(' · ')),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatMoney(c.amount, c.currency), style: const TextStyle(fontWeight: FontWeight.w600)),
          if (myShare != null)
            Text('te toca ${formatMoney(myShare, c.currency, compact: true)}',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      onTap: () => openExpenseForm(context, existing: e),
    );
  }
}
