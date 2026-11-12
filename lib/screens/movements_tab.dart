import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'dialogs.dart';
import 'expense_form_screen.dart';

int _day(Charge c) => switch (c.source) {
      Expense e => c.installment == 1 ? e.date.day : 1,
      RecurringExpense r => r.dayOfMonth,
      _ => 1,
    };

/// Suma de los cargos, separada por moneda: "$ 120.000 + US$ 12".
String chargesTotal(Iterable<Charge> charges) {
  final totals = <Currency, int>{};
  for (final c in charges) {
    totals[c.currency] = (totals[c.currency] ?? 0) + c.amount;
  }
  if (totals.isEmpty) return formatMoney(0, Currency.ars, compact: true);
  return [for (final e in totals.entries) formatMoney(e.value, e.key, compact: true)].join(' + ');
}

/// Lista de cargos agrupada por día, por quién pagó o por categoría, con el
/// subtotal de cada grupo.
List<Widget> chargeGroups(HouseholdState s, List<Charge> charges, GroupBy groupBy) {
  final sorted = [...charges]..sort((a, b) => _day(b).compareTo(_day(a)));
  final groups = <String, List<Charge>>{};
  final month = monthLabel(s.month).split(' ').first.toLowerCase();
  for (final c in sorted) {
    final key = switch (groupBy) {
      GroupBy.day => '${_day(c)} de $month',
      GroupBy.person => c.paidBy == s.me ? 'Pagaste vos' : 'Pagó ${s.nameOf(c.paidBy)}',
      GroupBy.category => c.category,
    };
    groups.putIfAbsent(key, () => []).add(c);
  }
  var keys = groups.keys.toList();
  if (groupBy != GroupBy.day) {
    // Los grupos más grandes primero.
    int total(String k) => groups[k]!.fold(0, (a, c) => a + c.amount);
    keys.sort((a, b) => total(b).compareTo(total(a)));
    if (groupBy == GroupBy.person) {
      keys = [...keys.where((k) => k == 'Pagaste vos'), ...keys.where((k) => k != 'Pagaste vos')];
    }
  }
  return [
    for (final k in keys) ...[
      SectionHeader(
        k,
        dense: true,
        action: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _Subtotal(chargesTotal(groups[k]!)),
        ),
      ),
      for (final c in groups[k]!)
        ChargeTile(c, showDay: groupBy != GroupBy.day, showPayer: groupBy != GroupBy.person),
    ],
  ];
}

class _Subtotal extends StatelessWidget {
  const _Subtotal(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: Theme.of(context)
          .textTheme
          .labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
}

class MovementsTab extends StatelessWidget {
  const MovementsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final all = s.monthCharges;
    final charges = all
        .where((c) =>
            (s.filterPayer == null || c.paidBy == s.filterPayer) &&
            (s.filterShared == null || c.isShared == s.filterShared))
        .toList();
    final filtering = s.filterPayer != null || s.filterShared != null;
    final incomes = s.filterShared != null
        ? <Income>[]
        : s.incomes
            .where((i) =>
                i.month == s.month && (s.filterPayer == null || i.memberId == s.filterPayer))
            .toList();
    final settlements = filtering
        ? <Settlement>[]
        : (s.settlements.where((x) => YearMonth.fromDate(x.date) == s.month).toList()
          ..sort((a, b) => b.date.compareTo(a.date)));

    // Gastos fijos marcados como "este mes no se paga".
    final skipped = filtering
        ? <RecurringExpense>[]
        : s.recurring.where((r) => r.activeIn(s.month) && r.amountIn(s.month) <= 0).toList();

    final empty = charges.isEmpty && incomes.isEmpty && settlements.isEmpty && skipped.isEmpty;

    return Column(
      children: [
        const MonthHeader(),
        const _FilterBar(),
        Expanded(
          child: MonthSwiper(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                if (charges.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Row(children: [
                      Expanded(
                        child: Text(
                          '${charges.length} ${charges.length == 1 ? 'gasto' : 'gastos'}'
                          '${filtering ? ' con este filtro' : ''}',
                          style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Text(chargesTotal(charges), style: t.titleMedium),
                    ]),
                  ),
                if (empty)
                  Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(children: [
                      Icon(Icons.receipt_long_outlined, size: 56, color: scheme.outline),
                      const SizedBox(height: 12),
                      Text(
                          filtering && all.isNotEmpty
                              ? 'Ningún gasto coincide con el filtro'
                              : 'No hay movimientos este mes',
                          style: t.titleMedium,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      if (filtering && all.isNotEmpty)
                        TextButton(
                          onPressed: () => s.setFilter(payer: () => null, shared: () => null),
                          child: const Text('Quitar filtros'),
                        )
                      else
                        Text('Tocá "Gasto" para cargar el primero.',
                            style: t.bodyMedium, textAlign: TextAlign.center),
                    ]),
                  ),
                ...chargeGroups(s, charges, s.groupBy),
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
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
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
                        backgroundColor: scheme.secondaryContainer,
                        foregroundColor: scheme.onSecondaryContainer,
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

/// Filtros de la lista: quién pagó, compartidos o personales, y cómo agrupar.
class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final partner = s.partner;
    const groupLabels = {
      GroupBy.day: 'Por día',
      GroupBy.person: 'Por persona',
      GroupBy.category: 'Por categoría',
    };
    Widget gap() => const SizedBox(width: 8);
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          PopupMenuButton<GroupBy>(
            tooltip: 'Agrupar la lista',
            initialValue: s.groupBy,
            onSelected: (g) => s.setFilter(group: g),
            itemBuilder: (_) => [
              for (final e in groupLabels.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
            child: Chip(
              avatar: const Icon(Icons.sort, size: 18),
              label: Text(groupLabels[s.groupBy]!),
            ),
          ),
          gap(),
          const Center(child: SizedBox(height: 24, child: VerticalDivider(width: 1))),
          gap(),
          if (partner != null) ...[
            FilterChip(
              label: const Text('Pagué yo'),
              selected: s.filterPayer == s.me,
              onSelected: (on) => s.setFilter(payer: () => on ? s.me : null),
            ),
            gap(),
            FilterChip(
              label: Text('Pagó ${partner.name}'),
              selected: s.filterPayer == partner.id,
              onSelected: (on) => s.setFilter(payer: () => on ? partner.id : null),
            ),
            gap(),
          ],
          FilterChip(
            label: const Text('Compartidos'),
            selected: s.filterShared == true,
            onSelected: (on) => s.setFilter(shared: () => on ? true : null),
          ),
          gap(),
          FilterChip(
            label: const Text('Personales'),
            selected: s.filterShared == false,
            onSelected: (on) => s.setFilter(shared: () => on ? false : null),
          ),
        ],
      ),
    );
  }
}

class ChargeTile extends StatelessWidget {
  const ChargeTile(this.c, {super.key, this.showDay = false, this.showPayer = true});
  final Charge c;

  /// Muestra el día en el renglón (cuando la lista no está agrupada por día).
  final bool showDay;
  final bool showPayer;

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final e = c.source;
    final tags = <String>[
      if (showDay) 'Día ${_day(c)}',
      if (showPayer) 'Pagó ${s.nameOf(e.paidBy)}',
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

/// Detalle de una categoría en el mes: los gastos compartidos en [currency],
/// agrupados por quién pagó o por día.
Future<void> openCategoryDetail(BuildContext context, String category, Currency currency) {
  final s = HouseholdScope.of(context);
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => HouseholdScope(
        state: s, child: _CategoryDetailScreen(category: category, currency: currency)),
  ));
}

class _CategoryDetailScreen extends StatefulWidget {
  const _CategoryDetailScreen({required this.category, required this.currency});
  final String category;
  final Currency currency;

  @override
  State<_CategoryDetailScreen> createState() => _CategoryDetailScreenState();
}

class _CategoryDetailScreenState extends State<_CategoryDetailScreen> {
  GroupBy _group = GroupBy.person;

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final charges = s.monthCharges
        .where((c) =>
            c.isShared && c.category == widget.category && c.currency == widget.currency)
        .toList();
    final total = charges.fold(0, (a, c) => a + c.amount);
    final mine = charges.fold(
        0, (a, c) => a + (shareAmounts(c.amount, c.source.split)[s.me] ?? 0));
    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: SafeArea(
        child: ContentWidth(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gastos compartidos · ${monthLabel(s.month)}',
                      style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(formatMoney(total, widget.currency),
                        style: t.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    '${charges.length} ${charges.length == 1 ? 'gasto' : 'gastos'}'
                    '${s.partner == null ? '' : ' · te toca ${formatMoney(mine, widget.currency, compact: true)}'}',
                    style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<GroupBy>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: GroupBy.person, label: Text('Por persona')),
                      ButtonSegment(value: GroupBy.day, label: Text('Por día')),
                    ],
                    selected: {_group},
                    onSelectionChanged: (v) => setState(() => _group = v.first),
                  ),
                ]),
              ),
              if (charges.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('No hay gastos de esta categoría este mes.',
                      textAlign: TextAlign.center),
                ),
              ...chargeGroups(s, charges, _group),
            ],
          ),
        ),
      ),
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
