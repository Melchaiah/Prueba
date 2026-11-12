import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/common.dart';

/// Renglón con el avance de una meta: nombre, ahorrado de objetivo y barra.
class GoalMeter extends StatelessWidget {
  const GoalMeter(this.goal, {super.key, this.onTap});
  final Goal goal;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final g = goal;
    final needed = g.monthlyNeeded(YearMonth.now());
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(g.reached ? Icons.check_circle : Icons.savings_outlined,
                size: 18, color: g.reached ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(child: Text(g.name, overflow: TextOverflow.ellipsis)),
            Text(formatPercent((g.ratio * 100).roundToDouble()), style: t.titleSmall),
          ]),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: g.ratio,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          const SizedBox(height: 4),
          Text(
            '${formatMoney(g.saved, g.currency, compact: true)} de ${formatMoney(g.target, g.currency, compact: true)}'
            '${g.reached ? ' · ¡Meta cumplida!' : needed != null ? ' · ${formatMoney(needed, g.currency, compact: true)} por mes hasta ${monthLabel(g.deadline!).toLowerCase()}' : ''}',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}

/// Crea o edita una meta de ahorro.
Future<void> showGoalDialog(BuildContext context, {Goal? existing}) {
  final s = HouseholdScope.of(context);
  final form = GlobalKey<FormState>();
  final name = TextEditingController(text: existing?.name ?? '');
  final target =
      TextEditingController(text: existing == null ? '' : moneyToInput(existing.target));
  var currency = existing?.currency ?? s.mainCurrency;
  var deadline = existing?.deadline;
  final now = YearMonth.now();

  return showDialog(
    context: context,
    builder: (ctx) => HouseholdScope(
      state: s,
      child: StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'Nueva meta de ahorro' : 'Editar meta'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextFormField(
                  controller: name,
                  autofocus: existing == null,
                  decoration: const InputDecoration(
                      labelText: 'Para qué ahorran', hintText: 'Vacaciones, auto, fondo…'),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Ponele un nombre' : null,
                ),
                const SizedBox(height: 12),
                AmountField(controller: target, currency: currency, label: 'Cuánto quieren juntar'),
                const SizedBox(height: 12),
                CurrencyPicker(value: currency, onChanged: (v) => setState(() => currency = v)),
                const SizedBox(height: 12),
                DropdownButtonFormField<YearMonth?>(
                  initialValue: deadline,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Para cuándo (opcional)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Sin fecha')),
                    if (deadline != null && (deadline! < now || deadline! > now.add(36)))
                      DropdownMenuItem(value: deadline, child: Text(monthLabel(deadline!))),
                    for (var i = 0; i <= 36; i++)
                      DropdownMenuItem(value: now.add(i), child: Text(monthLabel(now.add(i)))),
                  ],
                  onChanged: (v) => setState(() => deadline = v),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final g = (existing ??
                        Goal(id: s.repo.newId(), name: '', target: 0, currency: currency))
                    .copyWith(
                  name: name.text.trim(),
                  target: parseMoney(target.text)!,
                  currency: currency,
                  deadline: () => deadline,
                );
                Navigator.pop(ctx);
                guard(context, s.repo.saveGoal(s.hid, g));
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Registra un aporte (o un retiro) a la meta.
Future<void> _showContributionDialog(BuildContext context, Goal goal, {bool withdraw = false}) {
  final s = HouseholdScope.of(context);
  final form = GlobalKey<FormState>();
  final amount = TextEditingController();
  var member = s.me;
  return showDialog(
    context: context,
    builder: (ctx) => HouseholdScope(
      state: s,
      child: StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(withdraw ? 'Retirar de ${goal.name}' : 'Aportar a ${goal.name}'),
          content: Form(
            key: form,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (s.partner != null) ...[
                  MemberPicker(value: member, onChanged: (v) => setState(() => member = v)),
                  const SizedBox(height: 12),
                ],
                AmountField(controller: amount, currency: goal.currency, autofocus: true),
                const SizedBox(height: 12),
                Text(
                  withdraw
                      ? 'Se descuenta de lo ahorrado.'
                      : 'El aporte no cuenta como gasto ni cambia el saldo entre ustedes.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final value = parseMoney(amount.text)!;
                // Se parte de la versión más nueva de la meta.
                final current = s.goals.where((g) => g.id == goal.id).firstOrNull ?? goal;
                Navigator.pop(ctx);
                guard(
                  context,
                  s.repo.saveGoal(
                    s.hid,
                    current.copyWith(contributions: [
                      ...current.contributions,
                      Contribution(
                          memberId: member,
                          amount: withdraw ? -value : value,
                          date: DateTime.now()),
                    ]),
                  ),
                );
              },
              child: Text(withdraw ? 'Retirar' : 'Aportar'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Detalle de una meta: avance, cuánto puso cada uno y los aportes.
Future<void> showGoalSheet(BuildContext context, String goalId) {
  final s = HouseholdScope.of(context);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => HouseholdScope(
      state: s,
      child: Builder(builder: (ctx) {
        final state = HouseholdScope.of(ctx);
        final g = state.goals.where((x) => x.id == goalId).firstOrNull;
        if (g == null) return const SizedBox(height: 80);
        final t = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        final history = g.contributions.reversed.toList();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                Row(children: [
                  Expanded(child: Text(g.name, style: t.titleLarge)),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Editar meta',
                    onPressed: () => showGoalDialog(context, existing: g),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Borrar meta',
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: Text('¿Borrar "${g.name}"?'),
                          content: const Text('Se borra la meta con todos sus aportes.'),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(d, false),
                                child: const Text('Cancelar')),
                            FilledButton(
                                onPressed: () => Navigator.pop(d, true),
                                child: const Text('Borrar')),
                          ],
                        ),
                      );
                      if (ok != true) return;
                      if (sheet.mounted) Navigator.pop(sheet);
                      if (context.mounted) guard(context, s.repo.deleteGoal(s.hid, g.id));
                    },
                  ),
                ]),
                GoalMeter(g),
                const SizedBox(height: 8),
                if (state.partner != null)
                  for (final id in state.memberIds)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(children: [
                        Expanded(
                            child: Text(id == state.me ? 'Pusiste vos' : 'Puso ${state.nameOf(id)}')),
                        Text(formatMoney(g.savedBy(id), g.currency, compact: true),
                            style: t.titleSmall),
                      ]),
                    ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Aportar'),
                      onPressed: () => _showContributionDialog(context, g),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.remove),
                      label: const Text('Retirar'),
                      onPressed:
                          g.saved <= 0 ? null : () => _showContributionDialog(context, g, withdraw: true),
                    ),
                  ),
                ]),
                if (history.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Movimientos de la meta',
                      style: t.titleSmall?.copyWith(color: scheme.primary)),
                  for (final c in history)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(c.memberId == state.me
                          ? (c.amount < 0 ? 'Retiraste vos' : 'Aportaste vos')
                          : '${state.nameOf(c.memberId)} ${c.amount < 0 ? 'retiró' : 'aportó'}'),
                      subtitle: Text(formatDate(c.date)),
                      trailing: Text(
                        '${c.amount < 0 ? '− ' : '+ '}${formatMoney(c.amount.abs(), g.currency, compact: true)}',
                        style: t.titleSmall,
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      }),
    ),
  );
}
