import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/month_selector.dart';
import 'dialogs.dart';

class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final summary = s.summary;
    final budgets = budgetStatuses(s.budgets, summary);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
      children: [
        const MonthSelector(),
        _BalanceCard(s),
        _IncomeCard(s, summary),
        _SharedCard(s, summary),
        if (budgets.isNotEmpty) _BudgetsCard(budgets),
        _PersonalCard(s, summary),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              ?action,
            ]),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ]),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard(this.s);
  final HouseholdState s;

  @override
  Widget build(BuildContext context) {
    final debts = <(Currency, Debt)>[];
    s.balances.forEach((c, net) {
      final d = debtFor(net);
      if (d != null && d.amount > 0) debts.add((c, d));
    });
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo entre ustedes', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (s.partner == null)
              const Text('Invitá a tu pareja desde Ajustes para empezar a compartir gastos.')
            else if (debts.isEmpty)
              Text('Están a mano 🎉', style: Theme.of(context).textTheme.headlineSmall)
            else
              for (final (c, d) in debts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        d.from == s.me
                            ? 'Le debés a ${s.nameOf(d.to)}'
                            : '${s.nameOf(d.from)} te debe',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    Text(formatMoney(d.amount, c),
                        style: Theme.of(context).textTheme.titleLarge),
                    IconButton(
                      icon: const Icon(Icons.handshake_outlined),
                      tooltip: 'Registrar pago',
                      onPressed: () => showSettlementDialog(context, d, c),
                    ),
                  ]),
                ),
            const SizedBox(height: 4),
            Text('Incluye cuotas y gastos fijos hasta este mes.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard(this.s, this.summary);
  final HouseholdState s;
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    final ars = s.proportional(Currency.ars);
    return _Section(
      title: 'Ingresos del mes',
      action: TextButton.icon(
        icon: const Icon(Icons.add),
        label: const Text('Ingreso'),
        onPressed: () => showIncomeDialog(context),
      ),
      children: [
        if (summary.income.isEmpty)
          const Text('Cargá los sueldos del mes para poder repartir gastos en proporción.'),
        for (final c in summary.income.keys)
          for (final id in s.memberIds)
            _Row(
              '${s.nameOf(id)}${c == Currency.ars && summary.income.isNotEmpty ? '  (${formatPercent(ars[id] ?? 0)})' : ''}',
              formatMoney(summary.income[c]?[id] ?? 0, c, compact: true),
            ),
      ],
    );
  }
}

class _SharedCard extends StatelessWidget {
  const _SharedCard(this.s, this.summary);
  final HouseholdState s;
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    if (summary.sharedTotal.isEmpty) {
      return const _Section(
          title: 'Gastos compartidos', children: [Text('Todavía no hay gastos este mes.')]);
    }
    return _Section(
      title: 'Gastos compartidos',
      children: [
        for (final c in summary.sharedTotal.keys) ...[
          _Row('Total ${c.code}', formatMoney(summary.sharedTotal[c]!, c), bold: true),
          for (final id in s.memberIds)
            _Row(
              '  ${s.nameOf(id)}: pagó ${formatMoney(summary.paidShared[c]?[id] ?? 0, c, compact: true)}',
              'le toca ${formatMoney(summary.shareOfShared[c]?[id] ?? 0, c, compact: true)}',
            ),
          const SizedBox(height: 8),
          _CategoryBars(summary.sharedByCategory[c]!, c),
          const Divider(),
        ],
      ],
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars(this.byCategory, this.currency);
  final Map<String, int> byCategory;
  final Currency currency;

  @override
  Widget build(BuildContext context) {
    final entries = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty ? 1 : entries.first.value;
    return Column(
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Row(e.key, formatMoney(e.value, currency, compact: true)),
                LinearProgressIndicator(value: e.value / max, minHeight: 6,
                    borderRadius: BorderRadius.circular(3)),
              ],
            ),
          ),
      ],
    );
  }
}

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard(this.statuses);
  final List<BudgetStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Section(
      title: 'Presupuestos',
      children: [
        for (final b in statuses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Row(
                  '${b.level == BudgetLevel.exceeded ? '⚠️ ' : ''}${b.budget.category}',
                  '${formatMoney(b.spent, b.budget.currency, compact: true)} / ${formatMoney(b.budget.limit, b.budget.currency, compact: true)}',
                ),
                LinearProgressIndicator(
                  value: b.ratio.clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  color: switch (b.level) {
                    BudgetLevel.ok => scheme.primary,
                    BudgetLevel.warning => Colors.orange,
                    BudgetLevel.exceeded => scheme.error,
                  },
                ),
                if (b.level != BudgetLevel.ok)
                  Text(
                    b.remaining < 0
                        ? 'Se pasaron por ${formatMoney(-b.remaining, b.budget.currency, compact: true)}'
                        : 'Quedan ${formatMoney(b.remaining, b.budget.currency, compact: true)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PersonalCard extends StatelessWidget {
  const _PersonalCard(this.s, this.summary);
  final HouseholdState s;
  final MonthSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Gastos personales',
      children: [
        if (summary.personal.isEmpty) const Text('Sin gastos personales visibles este mes.'),
        for (final c in summary.personal.keys)
          for (final e in summary.personal[c]!.entries)
            _Row(s.nameOf(e.key), formatMoney(e.value, c, compact: true)),
        const SizedBox(height: 4),
        Text('Solo se muestran los que cada uno eligió compartir.',
            style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
