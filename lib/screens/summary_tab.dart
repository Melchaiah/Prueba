import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'dialogs.dart';
import 'goals.dart';
import 'movements_tab.dart' show openCategoryDetail;

class SummaryTab extends StatelessWidget {
  const SummaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final summary = s.summary;
    final budgets = budgetStatuses(s.budgets, summary);
    // Monedas con algún dato este mes; la principal siempre primero.
    final used = <Currency>{
      s.mainCurrency,
      ...summary.sharedTotal.keys,
      ...summary.income.keys,
      ...summary.personal.keys,
    };
    return Column(
      children: [
        const MonthHeader(),
        Expanded(
          child: MonthSwiper(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (s.household?.wipe != null) WipeBanner(s),
                _BalanceCard(s),
                for (final c in used)
                  if (c == s.mainCurrency || summary.income.containsKey(c))
                    _PeopleCard(s, summary, c),
                for (final c in used)
                  if (summary.sharedTotal.containsKey(c)) _SharedCard(s, summary, c),
                if (summary.sharedTotal.isEmpty)
                  const SectionCard(title: 'Gastos compartidos', children: [
                    Text('Todavía no hay gastos este mes. Tocá "Gasto" para cargar el primero.'),
                  ]),
                if (budgets.isNotEmpty) _BudgetsCard(budgets),
                _EvolutionCard(s),
                if (s.goals.isNotEmpty) _GoalsCard(s),
                if (s.fxEnabled) _FxCard(s),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Aviso del pedido de borrado de datos, con las acciones de cada parte.
class WipeBanner extends StatelessWidget {
  const WipeBanner(this.s, {super.key});
  final HouseholdState s;

  @override
  Widget build(BuildContext context) {
    final w = s.household!.wipe!;
    final scheme = Theme.of(context).colorScheme;
    final mine = w.requestedBy == s.me;
    final what = w.scope == WipeScope.all
        ? 'todos los datos del hogar'
        : 'los gastos, ingresos y pagos del hogar';
    return SectionCard(
      color: scheme.errorContainer,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.delete_sweep_outlined, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              w.approved
                  ? 'Borrando $what…'
                  : mine
                      ? 'Pediste borrar $what. Falta que ${s.partner?.name ?? 'tu pareja'} lo acepte.'
                      : '${s.nameOf(w.requestedBy)} pidió borrar $what. Si aceptás, no se puede deshacer.',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
        ]),
        if (!w.approved) ...[
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            TextButton(
              onPressed: () => guard(context, s.cancelWipe()),
              child: Text(mine ? 'Cancelar pedido' : 'Rechazar'),
            ),
            if (!mine) ...[
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: scheme.error, foregroundColor: scheme.onError),
                onPressed: () => guard(context, s.approveWipe()),
                child: const Text('Aceptar y borrar'),
              ),
            ],
          ]),
        ],
      ],
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
    final t = Theme.of(context).textTheme;
    final on = scheme.onPrimaryContainer;
    return SectionCard(
      color: scheme.primaryContainer,
      children: [
        const SizedBox(height: 4),
        Text('Saldo entre ustedes', style: t.labelLarge?.copyWith(color: on)),
        const SizedBox(height: 8),
        if (s.partner == null)
          Text('Invitá a tu pareja desde Ajustes para empezar a compartir gastos.',
              style: t.bodyLarge?.copyWith(color: on))
        else if (debts.isEmpty)
          Row(children: [
            Icon(Icons.check_circle_outline, color: on, size: 32),
            const SizedBox(width: 12),
            Text('Están a mano', style: t.headlineSmall?.copyWith(color: on)),
          ])
        else
          for (final (c, d) in debts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      d.from == s.me
                          ? 'Le debés a ${s.nameOf(d.to)}'
                          : '${s.nameOf(d.from)} te debe',
                      style: t.bodyMedium?.copyWith(color: on),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatMoney(d.amount, c),
                        style: t.headlineMedium?.copyWith(color: on, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.handshake_outlined),
                  label: const Text('Saldar'),
                  onPressed: () => showSettlementDialog(context, d, c),
                ),
              ]),
            ),
        const SizedBox(height: 4),
        Text('Cuenta cuotas y gastos fijos hasta hoy.',
            style: t.bodySmall?.copyWith(color: on.withValues(alpha: 0.8))),
      ],
    );
  }
}

/// Ingresos, gastos y lo que le queda a cada uno en el mes.
class _PeopleCard extends StatelessWidget {
  const _PeopleCard(this.s, this.summary, this.c);
  final HouseholdState s;
  final MonthSummary summary;
  final Currency c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final income = summary.income[c] ?? const {};
    final share = summary.shareOfShared[c] ?? const {};
    final personal = summary.personal[c] ?? const {};
    final hasIncome = income.values.any((v) => v > 0);
    final split = s.proportional(c);
    final ids = s.memberIds;

    Widget cell(String text, {TextStyle? style, bool end = true}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: end ? Alignment.centerRight : Alignment.centerLeft,
            child: Text(text, style: style),
          ),
        );

    TableRow row(String label, int Function(String id) value, {bool bold = false}) => TableRow(
          children: [
            cell(label, end: false, style: bold ? t.titleSmall : t.bodyMedium),
            for (final id in ids)
              cell(formatMoney(value(id), c, compact: true),
                  style: bold ? t.titleSmall : t.bodyMedium),
          ],
        );

    final multi = s.currencies.length > 1 || c != s.mainCurrency;
    return SectionCard(
      title: 'Cómo viene el mes${multi ? ' · ${c.code}' : ''}',
      action: c == s.mainCurrency
          ? TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Ingreso'),
              onPressed: () => showIncomeDialog(context),
            )
          : null,
      children: [
        Table(
          columnWidths: const {0: FlexColumnWidth(1.25)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(children: [
              const SizedBox.shrink(),
              for (final id in ids)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    MemberAvatar(s.household?.member(id)?.name ?? '?',
                        highlight: id == s.me, radius: 16),
                    const SizedBox(height: 4),
                    Text(s.nameOf(id), style: t.labelLarge, overflow: TextOverflow.ellipsis),
                    if (hasIncome)
                      Text('${formatPercent(split[id] ?? 0)} del ingreso',
                          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ]),
                ),
            ]),
            row('Ingresos', (id) => income[id] ?? 0),
            row('Parte compartida', (id) => -(share[id] ?? 0)),
            row('Personales', (id) => -(personal[id] ?? 0)),
            TableRow(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              children: [
                cell('Le queda', end: false, style: t.titleSmall),
                for (final id in ids)
                  cell(
                    formatMoney(
                        (income[id] ?? 0) - (share[id] ?? 0) - (personal[id] ?? 0), c,
                        compact: true),
                    style: t.titleSmall,
                  ),
              ],
            ),
          ],
        ),
        if (!hasIncome) ...[
          const SizedBox(height: 8),
          Text('Cargá los sueldos del mes para ver cuánto le queda a cada uno y poder repartir en proporción.',
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ] else if (s.partner != null && s.partner!.privacy != PrivacyMode.allVisible) ...[
          const SizedBox(height: 8),
          Text('De ${s.partner!.name} solo se cuentan los gastos personales que comparte con vos.',
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

/// Total compartido del mes y ranking por categoría (barras de un solo
/// color, de mayor a menor: se comparan mejor que una torta).
class _SharedCard extends StatelessWidget {
  const _SharedCard(this.s, this.summary, this.c);
  final HouseholdState s;
  final MonthSummary summary;
  final Currency c;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final total = summary.sharedTotal[c]!;
    final entries = summary.sharedByCategory[c]!.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    final paid = summary.paidShared[c] ?? const {};
    return SectionCard(
      title: 'Gastos compartidos',
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(formatMoney(total, c),
              style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 2),
        Text(
          [
            for (final id in s.memberIds)
              '${id == s.me ? 'Pagaste' : '${s.nameOf(id)} pagó'} ${formatMoney(paid[id] ?? 0, c, compact: true)}',
          ].join(' · '),
          style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        if (c == Currency.usd && s.fxEnabled && s.usdQuote != null)
          Text(
            'Equivale a ${formatMoney(usdToArs(total, s.usdQuote!.rate), Currency.ars, compact: true)} '
            'al dólar ${s.fx.source.label}',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        const SizedBox(height: 8),
        Text('Tocá una categoría para ver el detalle.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        for (final e in entries)
          Semantics(
            button: true,
            label:
                '${e.key}: ${formatMoney(e.value, c, compact: true)}, ${formatPercent((e.value * 100 / total).roundToDouble())} del total. Ver detalle',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => openCategoryDetail(context, e.key, c),
              child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(categoryIcon(e.key), size: 18, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(child: Text(e.key, overflow: TextOverflow.ellipsis)),
                  Text(formatMoney(e.value, c, compact: true), style: t.titleSmall),
                  SizedBox(
                    width: 44,
                    child: Text(
                      formatPercent((e.value * 100 / total).roundToDouble()),
                      textAlign: TextAlign.end,
                      style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
                ]),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: e.value / max,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ]),
            )),
          ),
      ],
    );
  }
}

/// Gasto compartido de los últimos meses. Una sola serie: barras de un
/// color, con el mes que se está mirando resaltado. Tocar una barra lleva a
/// ese mes.
class _EvolutionCard extends StatelessWidget {
  const _EvolutionCard(this.s);
  final HouseholdState s;

  static const _months = 6;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final now = YearMonth.now();
    final last = s.month >= now.add(-(_months - 1)) ? (s.month > now ? s.month : now) : s.month;
    final c = s.mainCurrency;
    final data = sharedTotalsByMonth(
      last: last,
      count: _months,
      currency: c,
      expenses: s.expenses,
      recurring: s.recurring,
    );
    final max = data.fold(0, (a, e) => e.$2 > a ? e.$2 : a);
    final current = data.firstWhere((e) => e.$1 == s.month).$2;
    final previous = data.where((e) => e.$1 == s.month.add(-1)).firstOrNull?.$2;
    String short(YearMonth m) => monthLabel(m).substring(0, 3).toLowerCase();
    String name(YearMonth m) => monthLabel(m).split(' ').first.toLowerCase();

    String? change;
    IconData? changeIcon;
    if (previous != null && previous > 0 && current > 0) {
      final pct = ((current - previous) * 100 / previous).round();
      if (pct == 0) {
        change = 'Igual que en ${name(s.month.add(-1))}';
        changeIcon = Icons.trending_flat;
      } else {
        change = '${pct.abs()}% ${pct > 0 ? 'más' : 'menos'} que en ${name(s.month.add(-1))}';
        changeIcon = pct > 0 ? Icons.trending_up : Icons.trending_down;
      }
    }

    return SectionCard(
      title: 'Evolución mes a mes',
      children: [
        Text('Gasto compartido en ${name(s.month)}',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(formatMoney(current, c, compact: true),
              style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        ),
        if (change != null)
          Row(children: [
            Icon(changeIcon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(change, style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 148,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (m, v) in data)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: m == s.month,
                    label: '${monthLabel(m)}: ${formatMoney(v, c, compact: true)}',
                    excludeSemantics: true,
                    child: Tooltip(
                      message: '${monthLabel(m)}: ${formatMoney(v, c, compact: true)}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => s.setMonth(m),
                        child: Column(children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: max == 0 ? 0.02 : (v / max).clamp(0.02, 1.0),
                                  child: Container(
                                    constraints: const BoxConstraints(maxWidth: 36),
                                    decoration: BoxDecoration(
                                      color: m == s.month
                                          ? scheme.primary
                                          : scheme.primary.withValues(alpha: 0.35),
                                      borderRadius:
                                          const BorderRadius.vertical(top: Radius.circular(4)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(height: 1, color: scheme.outlineVariant),
                          const SizedBox(height: 6),
                          Text(
                            short(m),
                            style: t.labelMedium?.copyWith(
                              color: m == s.month ? scheme.onSurface : scheme.onSurfaceVariant,
                              fontWeight: m == s.month ? FontWeight.w700 : null,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('Tocá un mes para verlo. Incluye cuotas y gastos fijos'
            '${s.currencies.length > 1 ? ', solo en ${c.code}' : ''}.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

/// Avance de las metas de ahorro.
class _GoalsCard extends StatelessWidget {
  const _GoalsCard(this.s);
  final HouseholdState s;

  @override
  Widget build(BuildContext context) => SectionCard(
        title: 'Metas de ahorro',
        children: [for (final g in s.goals) GoalMeter(g, onTap: () => showGoalSheet(context, g.id))],
      );
}

/// Cotización del dólar que usa el hogar.
class _FxCard extends StatelessWidget {
  const _FxCard(this.s);
  final HouseholdState s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final q = s.usdQuote;
    return SectionCard(children: [
      Row(children: [
        Icon(Icons.currency_exchange, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dólar ${s.fx.source.label}',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            Text(
              q != null
                  ? formatMoney(q.rate, Currency.ars)
                  : s.fxLoading
                      ? 'Consultando…'
                      : s.fx.source == FxSource.manual
                          ? 'Cargá el valor en Ajustes'
                          : 'Sin conexión',
              style: t.titleMedium,
            ),
            if (q?.date != null)
              Text('Actualizado el ${formatDate(q!.date!)}',
                  style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ]),
        ),
        if (s.fx.source != FxSource.manual)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar cotización',
            onPressed: s.fxLoading ? null : s.refreshFx,
          ),
      ]),
    ]);
  }
}

class _BudgetsCard extends StatelessWidget {
  const _BudgetsCard(this.statuses);
  final List<BudgetStatus> statuses;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final warning = scheme.brightness == Brightness.dark
        ? const Color(0xFFFFB95C)
        : const Color(0xFF9A5B00);
    return SectionCard(
      title: 'Presupuestos',
      children: [
        for (final b in statuses)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(b.budget.category, overflow: TextOverflow.ellipsis)),
                Text(
                  '${formatMoney(b.spent, b.budget.currency, compact: true)} de ${formatMoney(b.budget.limit, b.budget.currency, compact: true)}',
                  style: t.bodyMedium,
                ),
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: b.ratio.clamp(0, 1).toDouble(),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
                backgroundColor: scheme.surfaceContainerHighest,
                color: switch (b.level) {
                  BudgetLevel.ok => scheme.primary,
                  BudgetLevel.warning => warning,
                  BudgetLevel.exceeded => scheme.error,
                },
              ),
              if (b.level != BudgetLevel.ok)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(
                      b.level == BudgetLevel.exceeded
                          ? Icons.error_outline
                          : Icons.warning_amber_outlined,
                      size: 16,
                      color: b.level == BudgetLevel.exceeded ? scheme.error : warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: Text(
                      b.remaining < 0
                          ? 'Se pasaron por ${formatMoney(-b.remaining, b.budget.currency, compact: true)}'
                          : 'Cerca del tope: quedan ${formatMoney(b.remaining, b.budget.currency, compact: true)}',
                      style: t.bodySmall,
                    )),
                  ]),
                ),
            ]),
          ),
      ],
    );
  }
}
