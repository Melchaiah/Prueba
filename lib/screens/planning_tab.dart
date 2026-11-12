import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import 'dialogs.dart';
import 'expense_form_screen.dart';
import '../widgets/common.dart';

class PlanningTab extends StatelessWidget {
  const PlanningTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final now = YearMonth.now();
    final active = s.recurring.where((r) => r.end == null || r.end! >= now).toList()
      ..sort((a, b) => a.dayOfMonth.compareTo(b.dayOfMonth));
    final ended = s.recurring.where((r) => r.end != null && r.end! < now).toList();

    // Compras en cuotas que todavía tienen cuotas por pagar.
    final pending = s.expenses.where((e) => e.installments > 1 && e.lastInstallment > now).toList()
      ..sort((a, b) => a.lastInstallment.compareTo(b.lastInstallment));
    final pendingTotals = <Currency, int>{};
    for (final e in pending) {
      var rest = 0;
      for (var n = 1; n <= e.installments; n++) {
        if (e.firstInstallment.add(n - 1) > now) rest += installmentAmount(e.amount, e.installments, n);
      }
      pendingTotals[e.currency] = (pendingTotals[e.currency] ?? 0) + rest;
    }

    return ContentWidth(child: ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        SectionHeader(
          'Gastos fijos mensuales',
          action: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
            onPressed: () => openExpenseForm(context),
          ),
        ),
        if (active.isEmpty)
          const _Empty('Alquiler, servicios, suscripciones… Cargalos una vez y se repiten solos.'),
        for (final r in active)
          ListTile(
            leading: CategoryAvatar(r.category, personal: !r.isShared),
            title: Text(r.description),
            subtitle: Text('Día ${r.dayOfMonth} · Paga ${s.nameOf(r.paidBy)}'
                '${r.isShared ? '' : ' · Personal'}'
                '${r.end != null ? ' · hasta ${monthLabel(r.end!)}' : ''}'),
            trailing: TrailingAmount(
              formatMoney(r.amount, r.currency),
              detail: r.overrides.containsKey(s.month) && r.activeIn(s.month)
                  ? r.amountIn(s.month) <= 0
                      ? 'no se paga en ${monthLabel(s.month).split(' ').first.toLowerCase()}'
                      : '${formatMoney(r.amountIn(s.month), r.currency, compact: true)} en ${monthLabel(s.month).split(' ').first.toLowerCase()}'
                  : null,
            ),
            onTap: () => openExpenseForm(context, existing: r),
          ),
        if (active.isNotEmpty) _totals(context, {
          for (final c in Currency.values)
            c: active.where((r) => r.currency == c).fold(0, (a, r) => a + r.amount),
        }, 'Total habitual por mes'),
        if (ended.isNotEmpty)
          ExpansionTile(
            title: Text('Finalizados (${ended.length})'),
            children: [
              for (final r in ended)
                ListTile(
                  title: Text(r.description),
                  subtitle: Text('${monthLabel(r.start)} – ${monthLabel(r.end!)}'),
                  trailing: TrailingAmount(formatMoney(r.amount, r.currency)),
                  onTap: () => openExpenseForm(context, existing: r),
                ),
            ],
          ),
        const SectionHeader('Cuotas pendientes'),
        if (pending.isEmpty) const _Empty('No hay compras en cuotas pendientes.'),
        for (final e in pending)
          ListTile(
            leading: CategoryAvatar(e.category, personal: !e.isShared),
            title: Text(e.description),
            subtitle: Text(
                'Cuota ${now.monthsSince(e.firstInstallment) + 1}/${e.installments} · termina en ${monthLabel(e.lastInstallment)}'),
            trailing: TrailingAmount('${formatMoney(installmentAmount(e.amount, e.installments, 2), e.currency)}/mes'),
            onTap: () => openExpenseForm(context, existing: e),
          ),
        if (pending.isNotEmpty) _totals(context, pendingTotals, 'Falta pagar (próximos meses)'),
        SectionHeader(
          'Presupuestos mensuales',
          action: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
            onPressed: () => showBudgetDialog(context),
          ),
        ),
        if (s.budgets.isEmpty)
          const _Empty('Poné un tope por categoría (ej. Salidas) y te avisamos al llegar al 80%.'),
        for (final b in s.budgets)
          ListTile(
            leading: CategoryAvatar(b.category),
            title: Text(b.category),
            subtitle: const Text('Tope de gasto compartido'),
            trailing: TrailingAmount(formatMoney(b.limit, b.currency, compact: true)),
            onTap: () => showBudgetDialog(context, existing: b),
          ),
      ],
    ));
  }

  Widget _totals(BuildContext context, Map<Currency, int> totals, String label) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold))),
          const SizedBox(width: 8),
          Text(
            [
              for (final e in totals.entries)
                if (e.value > 0) formatMoney(e.value, e.key, compact: true),
            ].join('\n+ '),
            textAlign: TextAlign.end,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
