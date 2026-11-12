import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';

String? validateAmount(String? v) =>
    (parseMoney(v ?? '') ?? 0) <= 0 ? 'Ingresá un monto válido' : null;

class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({super.key, required this.value, required this.onChanged});
  final Currency value;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<Currency>(
        segments: const [
          ButtonSegment(value: Currency.ars, label: Text('ARS')),
          ButtonSegment(value: Currency.usd, label: Text('USD')),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

class MemberPicker extends StatelessWidget {
  const MemberPicker({super.key, required this.state, required this.value, required this.onChanged});
  final HouseholdState state;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        segments: [
          for (final id in state.memberIds)
            ButtonSegment(value: id, label: Text(state.nameOf(id))),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      );
}

/// Carga (o edita) un ingreso del mes seleccionado.
Future<void> showIncomeDialog(BuildContext context, {Income? existing}) {
  final s = HouseholdScope.of(context);
  final form = GlobalKey<FormState>();
  final desc = TextEditingController(text: existing?.description ?? 'Sueldo');
  final amount = TextEditingController(
      text: existing == null ? '' : moneyToInput(existing.amount));
  var member = existing?.memberId ?? s.me;
  var currency = existing?.currency ?? Currency.ars;

  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('${existing == null ? 'Nuevo' : 'Editar'} ingreso · ${monthLabel(existing?.month ?? s.month)}'),
        content: Form(
          key: form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              MemberPicker(state: s, value: member, onChanged: (v) => setState(() => member = v)),
              const SizedBox(height: 12),
              TextFormField(controller: desc, decoration: const InputDecoration(labelText: 'Concepto')),
              TextFormField(
                controller: amount,
                decoration: const InputDecoration(labelText: 'Monto'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: validateAmount,
              ),
              const SizedBox(height: 12),
              CurrencyPicker(value: currency, onChanged: (v) => setState(() => currency = v)),
            ]),
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                s.repo.deleteIncome(s.hid, existing.id);
                Navigator.pop(ctx);
              },
              child: const Text('Borrar'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              s.repo.saveIncome(
                s.hid,
                Income(
                  id: existing?.id ?? s.repo.newId(),
                  memberId: member,
                  description: desc.text.trim().isEmpty ? 'Ingreso' : desc.text.trim(),
                  amount: parseMoney(amount.text)!,
                  currency: currency,
                  month: existing?.month ?? s.month,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}

/// Registra un pago entre la pareja para saldar (total o parcialmente).
Future<void> showSettlementDialog(BuildContext context, Debt debt, Currency currency) {
  final s = HouseholdScope.of(context);
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(text: moneyToInput(debt.amount));
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Registrar pago'),
      content: Form(
        key: form,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('${s.nameOf(debt.from)} le paga a ${s.nameOf(debt.to)}'),
          TextFormField(
            controller: amount,
            decoration: InputDecoration(labelText: 'Monto (${currency.code})'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: validateAmount,
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            s.repo.saveSettlement(
              s.hid,
              Settlement(
                id: s.repo.newId(),
                from: debt.from,
                to: debt.to,
                amount: parseMoney(amount.text)!,
                currency: currency,
                date: DateTime.now(),
              ),
            );
            Navigator.pop(ctx);
          },
          child: const Text('Registrar'),
        ),
      ],
    ),
  );
}

/// Crea o edita el tope mensual de una categoría.
Future<void> showBudgetDialog(BuildContext context, {Budget? existing}) {
  final s = HouseholdScope.of(context);
  final form = GlobalKey<FormState>();
  final used = s.budgets.map((b) => b.category).toSet();
  final options = [
    for (final c in defaultCategories)
      if (c == existing?.category || !used.contains(c)) c,
  ];
  if (options.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ya hay presupuesto para todas las categorías.')));
    return Future.value();
  }
  var category = existing?.category ?? options.first;
  var currency = existing?.currency ?? Currency.ars;
  final limit = TextEditingController(text: existing == null ? '' : moneyToInput(existing.limit));
  return showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(existing == null ? 'Nuevo presupuesto' : 'Editar presupuesto'),
        content: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in options) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: existing != null ? null : (v) => setState(() => category = v!),
            ),
            TextFormField(
              controller: limit,
              decoration: const InputDecoration(labelText: 'Tope mensual (compartido)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: validateAmount,
            ),
            const SizedBox(height: 12),
            CurrencyPicker(value: currency, onChanged: (v) => setState(() => currency = v)),
          ]),
        ),
        actions: [
          if (existing != null)
            TextButton(
              onPressed: () {
                s.repo.deleteBudget(s.hid, existing.id);
                Navigator.pop(ctx);
              },
              child: const Text('Borrar'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              s.repo.saveBudget(
                s.hid,
                Budget(
                  id: existing?.id ?? s.repo.newId(),
                  category: category,
                  limit: parseMoney(limit.text)!,
                  currency: currency,
                ),
              );
              Navigator.pop(ctx);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
