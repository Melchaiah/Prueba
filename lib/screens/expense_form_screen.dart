import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/finance.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../widgets/common.dart';
import 'dialogs.dart';

/// Abre el formulario para crear un gasto o editar uno existente
/// ([Expense] o [RecurringExpense]).
Future<void> openExpenseForm(BuildContext context, {ExpenseBase? existing}) {
  final s = HouseholdScope.of(context);
  if (existing != null && !existing.isShared && existing.paidBy != s.me) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Solo ${s.nameOf(existing.paidBy)} puede editar sus gastos personales.')));
    return Future.value();
  }
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => HouseholdScope(state: s, child: ExpenseFormScreen(existing: existing)),
  ));
}

enum _Frequency { once, installments, monthly }

enum _SplitPreset { equal, income, allMe, allPartner, custom }

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.existing});
  final ExpenseBase? existing;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _desc;
  late final TextEditingController _amount;
  late HouseholdState s;
  bool _initialized = false;

  bool _shared = true;
  late Currency _currency;
  String _category = defaultCategories.first;
  late String _paidBy;
  _SplitPreset _preset = _SplitPreset.income;
  double _myPercent = 50;
  _Frequency _freq = _Frequency.once;
  int _installments = 3;
  late YearMonth _firstInstallment;
  late DateTime _date;
  int _day = 1;
  bool _visible = true;

  Expense? get _expense => widget.existing is Expense ? widget.existing as Expense : null;
  RecurringExpense? get _recurring =>
      widget.existing is RecurringExpense ? widget.existing as RecurringExpense : null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    s = HouseholdScope.of(context);
    if (_initialized) return;
    _initialized = true;
    final e = widget.existing;
    _desc = TextEditingController(text: e?.description ?? '');
    _paidBy = e?.paidBy ?? s.me;
    _currency = e?.currency ?? s.mainCurrency;
    _date = _expense?.date ?? DateTime.now();
    _firstInstallment = _expense?.firstInstallment ?? s.month;
    _day = _recurring?.dayOfMonth ?? DateTime.now().day.clamp(1, 28);
    if (e == null) {
      _amount = TextEditingController();
      // Si no hay ingresos cargados, arrancar con 50/50.
      if (s.incomes.every((i) => i.month != s.month)) _preset = _SplitPreset.equal;
      return;
    }
    _shared = e.isShared;
    _currency = e.currency;
    _category = defaultCategories.contains(e.category) ? e.category : 'Otros';
    _visible = e.visibleToPartner;
    _myPercent = e.split[s.me] ?? 50;
    _preset = _SplitPreset.custom;
    if (_expense != null) {
      _amount = TextEditingController(text: moneyToInput(_expense!.amount));
      _installments = _expense!.installments;
      _freq = _installments > 1 ? _Frequency.installments : _Frequency.once;
      if (_installments < 2) _installments = 3;
    } else {
      _amount = TextEditingController(text: moneyToInput(_recurring!.amount));
      _freq = _Frequency.monthly;
    }
  }

  String? get _partnerId => s.partner?.id;

  Shares get _split {
    final p = _partnerId;
    if (!_shared || p == null) return {s.me: 100};
    return switch (_preset) {
      _SplitPreset.equal => equalSplit(s.memberIds),
      _SplitPreset.income => s.proportional(_currency),
      _SplitPreset.allMe => {s.me: 100, p: 0},
      _SplitPreset.allPartner => {s.me: 0, p: 100},
      _SplitPreset.custom => {s.me: _myPercent, p: 100 - _myPercent},
    };
  }

  Member? get _myMember => s.household?.member(s.me);

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseMoney(_amount.text)!;
    final desc = _desc.text.trim().isEmpty ? _category : _desc.text.trim();
    final paidBy = _shared ? _paidBy : s.me;
    final split = _split;
    if (_freq == _Frequency.monthly) {
      final r = _recurring;
      await s.repo.saveRecurring(
        s.hid,
        RecurringExpense(
          id: r?.id ?? s.repo.newId(),
          description: desc,
          category: _category,
          amount: amount,
          currency: _currency,
          paidBy: paidBy,
          isShared: _shared,
          split: split,
          dayOfMonth: _day,
          start: r?.start ?? s.month,
          end: r?.end,
          visibleToPartner: _visible,
          overrides: r?.overrides ?? const {},
        ),
      );
    } else {
      await s.repo.saveExpense(
        s.hid,
        Expense(
          id: _expense?.id ?? s.repo.newId(),
          description: desc,
          category: _category,
          amount: amount,
          currency: _currency,
          date: _date,
          paidBy: paidBy,
          isShared: _shared,
          split: split,
          installments: _freq == _Frequency.installments ? _installments : 1,
          firstInstallment:
              _freq == _Frequency.installments ? _firstInstallment : YearMonth.fromDate(_date),
          visibleToPartner: _visible,
        ),
      );
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar gasto?'),
        content: Text(_recurring != null
            ? 'Se borra el gasto fijo de todos los meses, también de los pasados. '
                'Si ya no lo pagan, usá "Dejar de repetir".'
            : 'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    if (_recurring != null) {
      await s.repo.deleteRecurring(s.hid, _recurring!.id);
    } else {
      await s.repo.deleteExpense(s.hid, _expense!.id);
    }
    if (mounted) Navigator.pop(context);
  }

  /// Termina un gasto fijo: deja de contar desde el mes que se está viendo.
  Future<void> _stopRecurring() async {
    final r = _recurring!;
    final end = s.month.add(-1);
    if (end < r.start) return _delete();
    await s.repo.saveRecurring(s.hid, r.copyWith(end: () => end));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final editing = widget.existing != null;
    final partner = s.partner;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? 'Editar gasto' : 'Nuevo gasto'),
        actions: [
          if (editing)
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Borrar', onPressed: _delete),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
              onPressed: _save,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ContentWidth(child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Compartido'), icon: Icon(Icons.people_outline)),
                ButtonSegment(value: false, label: Text('Personal'), icon: Icon(Icons.person_outline)),
              ],
              selected: {_shared},
              onSelectionChanged: (v) => setState(() => _shared = v.first),
            ),
            const SizedBox(height: 16),
            AmountField(
              controller: _amount,
              currency: _currency,
              autofocus: !editing,
              large: true,
              label: _freq == _Frequency.installments
                  ? 'Monto total (de todas las cuotas)'
                  : _freq == _Frequency.monthly
                      ? 'Monto por mes'
                      : 'Monto',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            CurrencyPicker(value: _currency, onChanged: (v) => setState(() => _currency = v)),
            const SizedBox(height: 16),
            TextFormField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Descripción (opcional)'),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [for (final c in defaultCategories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v!),
            ),
            if (_shared && partner != null) ...[
              const SizedBox(height: 20),
              Text('¿Quién pagó?', style: t.titleSmall),
              const SizedBox(height: 8),
              MemberPicker(value: _paidBy, onChanged: (v) => setState(() => _paidBy = v)),
              const SizedBox(height: 20),
              Text('¿Cómo se reparte?', style: t.titleSmall),
              const SizedBox(height: 8),
              _splitChips(partner),
              if (_preset == _SplitPreset.custom) _customSlider(partner),
              _splitPreview(),
            ],
            const SizedBox(height: 20),
            Text('Frecuencia', style: t.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<_Frequency>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _Frequency.once, label: const Text('Único'), enabled: _recurring == null),
                ButtonSegment(value: _Frequency.installments, label: const Text('En cuotas'), enabled: _recurring == null),
                ButtonSegment(value: _Frequency.monthly, label: const Text('Fijo mensual'), enabled: !editing || _recurring != null),
              ],
              selected: {_freq},
              onSelectionChanged: (v) => setState(() => _freq = v.first),
            ),
            const SizedBox(height: 12),
            ..._frequencyFields(),
            if (!_shared) ..._privacyFields(partner),
            if (_recurring != null && _recurring!.activeIn(s.month)) ...[
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.tune),
                label: Text('Ajustar solo ${monthLabel(s.month)}'),
                onPressed: () async {
                  final changed = await showMonthAdjustDialog(context, _recurring!, s.month);
                  if (changed && context.mounted) Navigator.pop(context);
                },
              ),
              const SizedBox(height: 4),
              Text(
                'Para meses en los que el monto es distinto (por ejemplo, la luz). '
                'Los cambios de arriba valen para todos los meses.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_recurring != null && _recurring!.end == null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text('Dejar de repetir desde ${monthLabel(s.month)}'),
                onPressed: _stopRecurring,
              ),
            ],
            const SizedBox(height: 32),
          ],
        )),
      ),
    );
  }

  Widget _splitChips(Member partner) {
    final prop = s.proportional(_currency);
    final hasIncome = s.incomes.any((i) => i.month == s.month && i.currency == _currency);
    Widget chip(_SplitPreset p, String label) => ChoiceChip(
          label: Text(label),
          selected: _preset == p,
          onSelected: (_) => setState(() {
            if (_preset != _SplitPreset.custom && p == _SplitPreset.custom) {
              _myPercent = _split[s.me] ?? 50;
            }
            _preset = p;
          }),
        );
    return Wrap(spacing: 8, runSpacing: 4, children: [
      chip(_SplitPreset.equal, '50 / 50'),
      chip(
        _SplitPreset.income,
        hasIncome
            ? 'Según ingresos (${formatPercent(prop[s.me] ?? 50)} / ${formatPercent(prop[partner.id] ?? 50)})'
            : 'Según ingresos (sin datos)',
      ),
      chip(_SplitPreset.allMe, 'Todo mío'),
      chip(_SplitPreset.allPartner, 'Todo de ${partner.name}'),
      chip(_SplitPreset.custom, 'Personalizado'),
    ]);
  }

  Widget _customSlider(Member partner) => Column(children: [
        Slider(
          value: _myPercent,
          min: 0,
          max: 100,
          divisions: 20,
          label: formatPercent(_myPercent),
          onChanged: (v) => setState(() => _myPercent = v),
        ),
        Row(children: [
          Text('Vos ${formatPercent(_myPercent)}'),
          const Spacer(),
          Text('${partner.name} ${formatPercent(100 - _myPercent)}'),
        ]),
      ]);

  Widget _splitPreview() {
    final amount = parseMoney(_amount.text);
    if (amount == null || amount <= 0) return const SizedBox.shrink();
    final perCharge = _freq == _Frequency.installments
        ? installmentAmount(amount, _installments, 1)
        : amount;
    final shares = shareAmounts(perCharge, _split);
    final suffix = switch (_freq) {
      _Frequency.installments => ' por cuota',
      _Frequency.monthly => ' por mes',
      _ => '',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        [
          for (final e in shares.entries)
            '${s.nameOf(e.key)}: ${formatMoney(e.value, _currency)}',
        ].join('  ·  ') + suffix,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  List<Widget> _frequencyFields() {
    switch (_freq) {
      case _Frequency.once:
        return [_dateTile()];
      case _Frequency.installments:
        final amount = parseMoney(_amount.text);
        return [
          _dateTile(label: 'Fecha de compra'),
          Row(children: [
            const Text('Cuotas'),
            const Spacer(),
            DropdownButton<int>(
              value: _installments,
              items: [
                for (final n in [2, 3, 4, 5, 6, 9, 10, 12, 18, 24])
                  DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: (v) => setState(() => _installments = v!),
            ),
          ]),
          Row(children: [
            const Text('Primera cuota'),
            const Spacer(),
            DropdownButton<YearMonth>(
              value: _firstInstallment,
              items: [
                for (var i = -2; i <= 2; i++)
                  () {
                    final m = YearMonth.fromDate(_date).add(i);
                    return DropdownMenuItem(value: m, child: Text(monthLabel(m)));
                  }(),
                if ((_firstInstallment.monthsSince(YearMonth.fromDate(_date))).abs() > 2)
                  DropdownMenuItem(value: _firstInstallment, child: Text(monthLabel(_firstInstallment))),
              ],
              onChanged: (v) => setState(() => _firstInstallment = v!),
            ),
          ]),
          if (amount != null && amount > 0)
            Text(
              '$_installments cuotas de ${formatMoney(installmentAmount(amount, _installments, 2), _currency)} '
              '· última en ${monthLabel(_firstInstallment.add(_installments - 1))}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ];
      case _Frequency.monthly:
        return [
          Row(children: [
            const Text('Día del mes'),
            const Spacer(),
            DropdownButton<int>(
              value: _day,
              items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
              onChanged: (v) => setState(() => _day = v!),
            ),
          ]),
          Text(
            _recurring != null
                ? 'Se repite desde ${monthLabel(_recurring!.start)}'
                    '${_recurring!.end != null ? ' hasta ${monthLabel(_recurring!.end!)}' : ''}.'
                : 'Se va a repetir todos los meses desde ${monthLabel(s.month)}.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
    }
  }

  Widget _dateTile({String label = 'Fecha'}) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.calendar_today),
        title: Text(label),
        trailing: Text(formatDate(_date)),
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (d != null) {
            setState(() {
              // Mantiene la primera cuota relativa a la nueva fecha.
              final offset = _firstInstallment.monthsSince(YearMonth.fromDate(_date));
              _date = d;
              _firstInstallment = YearMonth.fromDate(d).add(offset.clamp(-2, 2));
            });
          }
        },
      );

  List<Widget> _privacyFields(Member? partner) {
    if (partner == null) return const [];
    final mode = _myMember?.privacy ?? PrivacyMode.allVisible;
    return [
      const SizedBox(height: 20),
      if (mode == PrivacyMode.perExpense)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('Visible para ${partner.name}'),
          subtitle: Text(_visible
              ? '${partner.name} va a ver este gasto.'
              : 'Solo vos vas a ver este gasto.'),
          value: _visible,
          onChanged: (v) => setState(() => _visible = v),
        )
      else
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(mode == PrivacyMode.allVisible ? Icons.visibility : Icons.visibility_off),
          title: Text(mode == PrivacyMode.allVisible
              ? '${partner.name} va a ver este gasto'
              : 'Solo vos vas a ver este gasto'),
          subtitle: const Text('Lo podés cambiar en Ajustes › Privacidad.'),
        ),
    ];
  }
}
