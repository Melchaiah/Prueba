// Cálculos financieros puros (sin Firebase ni UI), fáciles de testear.

import '../models/models.dart';

/// Un cargo concreto que cae en un mes: una cuota de un gasto, un gasto de
/// pago único o la ocurrencia mensual de un gasto recurrente.
class Charge {
  final ExpenseBase source;
  final YearMonth month;
  final int amount; // centavos
  final int installment; // 1-based
  final int totalInstallments;
  final bool recurring;

  const Charge({
    required this.source,
    required this.month,
    required this.amount,
    this.installment = 1,
    this.totalInstallments = 1,
    this.recurring = false,
  });

  Currency get currency => source.currency;
  bool get isShared => source.isShared;
  String get category => source.category;
  String get paidBy => source.paidBy;
}

/// Monto de la cuota [n] (1-based). El resto de la división va a la primera
/// cuota para que la suma dé exactamente el total.
int installmentAmount(int total, int count, int n) {
  final base = total ~/ count;
  final remainder = total - base * count;
  return n == 1 ? base + remainder : base;
}

/// Cargos de un gasto que caen en [month] (0 o 1).
Charge? chargeOfExpenseIn(Expense e, YearMonth month) {
  if (month < e.firstInstallment || month > e.lastInstallment) return null;
  final n = month.monthsSince(e.firstInstallment) + 1;
  return Charge(
    source: e,
    month: month,
    amount: installmentAmount(e.amount, e.installments, n),
    installment: n,
    totalInstallments: e.installments,
  );
}

/// Todos los cargos (gastos, cuotas y recurrentes) de un mes.
List<Charge> chargesForMonth(
  YearMonth month,
  Iterable<Expense> expenses,
  Iterable<RecurringExpense> recurring,
) {
  final out = <Charge>[];
  for (final e in expenses) {
    final c = chargeOfExpenseIn(e, month);
    if (c != null) out.add(c);
  }
  for (final r in recurring) {
    if (r.activeIn(month)) {
      out.add(Charge(source: r, month: month, amount: r.amount, recurring: true));
    }
  }
  return out;
}

/// Todos los cargos desde el inicio hasta [upTo] inclusive. Las cuotas
/// futuras no cuentan todavía para el saldo.
List<Charge> chargesUpTo(
  YearMonth upTo,
  Iterable<Expense> expenses,
  Iterable<RecurringExpense> recurring,
) {
  final out = <Charge>[];
  for (final e in expenses) {
    for (var n = 1; n <= e.installments; n++) {
      final m = e.firstInstallment.add(n - 1);
      if (m > upTo) break;
      out.add(Charge(
        source: e,
        month: m,
        amount: installmentAmount(e.amount, e.installments, n),
        installment: n,
        totalInstallments: e.installments,
      ));
    }
  }
  for (final r in recurring) {
    final last = (r.end != null && r.end! < upTo) ? r.end! : upTo;
    for (var m = r.start; m <= last; m = m.add(1)) {
      out.add(Charge(source: r, month: m, amount: r.amount, recurring: true));
    }
  }
  return out;
}

/// Reparte [amount] según los porcentajes de [split]. Redondea a centavos y
/// asigna la diferencia de redondeo al miembro con mayor porcentaje, así la
/// suma es exacta.
Map<String, int> shareAmounts(int amount, Shares split) {
  if (split.isEmpty) return {};
  final total = split.values.fold<double>(0, (a, b) => a + b);
  if (total <= 0) return {};
  final out = <String, int>{};
  var assigned = 0;
  String? biggest;
  for (final entry in split.entries) {
    final v = (amount * entry.value / total).round();
    out[entry.key] = v;
    assigned += v;
    if (biggest == null || entry.value > split[biggest]!) biggest = entry.key;
  }
  out[biggest!] = out[biggest]! + (amount - assigned);
  return out;
}

/// Saldo neto de cada miembro, por moneda. Positivo = le deben;
/// negativo = debe. Solo cuentan los gastos compartidos.
Map<Currency, Map<String, int>> computeBalances({
  required Iterable<String> memberIds,
  required Iterable<Charge> charges,
  required Iterable<Settlement> settlements,
}) {
  final result = <Currency, Map<String, int>>{};
  Map<String, int> forCurrency(Currency c) =>
      result.putIfAbsent(c, () => {for (final id in memberIds) id: 0});

  for (final c in charges) {
    if (!c.isShared) continue;
    final net = forCurrency(c.currency);
    net[c.paidBy] = (net[c.paidBy] ?? 0) + c.amount;
    shareAmounts(c.amount, c.source.split).forEach((id, owed) {
      net[id] = (net[id] ?? 0) - owed;
    });
  }
  for (final s in settlements) {
    final net = forCurrency(s.currency);
    net[s.from] = (net[s.from] ?? 0) + s.amount;
    net[s.to] = (net[s.to] ?? 0) - s.amount;
  }
  return result;
}

/// Deuda resultante para una pareja en una moneda.
class Debt {
  final String from;
  final String to;
  final int amount;
  const Debt(this.from, this.to, this.amount);
}

/// Con dos personas, el que tiene saldo negativo le debe al otro.
Debt? debtFor(Map<String, int> net) {
  final entries = net.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
  if (entries.length < 2) return null;
  final debtor = entries.first;
  final creditor = entries.last;
  if (debtor.value >= 0) return null;
  return Debt(debtor.key, creditor.key, -debtor.value);
}

/// Reparto proporcional a los ingresos del mes en [currency]. Si nadie cargó
/// ingresos, devuelve partes iguales.
Shares proportionalSplit(
  Iterable<String> memberIds,
  Iterable<Income> incomes,
  YearMonth month, {
  Currency currency = Currency.ars,
}) {
  final ids = memberIds.toList();
  final totals = {for (final id in ids) id: 0};
  for (final i in incomes) {
    if (i.month == month && i.currency == currency && totals.containsKey(i.memberId)) {
      totals[i.memberId] = totals[i.memberId]! + i.amount;
    }
  }
  final sum = totals.values.fold<int>(0, (a, b) => a + b);
  if (sum == 0) return equalSplit(ids);
  return {for (final id in ids) id: _round2(totals[id]! * 100 / sum)};
}

Shares equalSplit(List<String> ids) =>
    {for (final id in ids) id: _round2(100 / ids.length)};

double _round2(double v) => (v * 100).round() / 100;

/// Resumen de un mes.
class MonthSummary {
  /// Gasto compartido total por moneda.
  final Map<Currency, int> sharedTotal;

  /// Gasto compartido por categoría y moneda.
  final Map<Currency, Map<String, int>> sharedByCategory;

  /// Lo que pagó cada uno de gastos compartidos.
  final Map<Currency, Map<String, int>> paidShared;

  /// La parte que le corresponde a cada uno de los gastos compartidos.
  final Map<Currency, Map<String, int>> shareOfShared;

  /// Gastos personales (los visibles para quien mira).
  final Map<Currency, Map<String, int>> personal;

  /// Ingresos de cada uno.
  final Map<Currency, Map<String, int>> income;

  const MonthSummary({
    required this.sharedTotal,
    required this.sharedByCategory,
    required this.paidShared,
    required this.shareOfShared,
    required this.personal,
    required this.income,
  });
}

MonthSummary summarizeMonth({
  required YearMonth month,
  required Iterable<Charge> charges,
  required Iterable<Income> incomes,
}) {
  final sharedTotal = <Currency, int>{};
  final byCat = <Currency, Map<String, int>>{};
  final paid = <Currency, Map<String, int>>{};
  final share = <Currency, Map<String, int>>{};
  final personal = <Currency, Map<String, int>>{};
  final income = <Currency, Map<String, int>>{};

  void addTo(Map<Currency, Map<String, int>> m, Currency c, String k, int v) {
    final inner = m.putIfAbsent(c, () => {});
    inner[k] = (inner[k] ?? 0) + v;
  }

  for (final c in charges) {
    if (c.month != month) continue;
    if (c.isShared) {
      sharedTotal[c.currency] = (sharedTotal[c.currency] ?? 0) + c.amount;
      addTo(byCat, c.currency, c.category, c.amount);
      addTo(paid, c.currency, c.paidBy, c.amount);
      shareAmounts(c.amount, c.source.split)
          .forEach((id, v) => addTo(share, c.currency, id, v));
    } else {
      addTo(personal, c.currency, c.paidBy, c.amount);
    }
  }
  for (final i in incomes) {
    if (i.month == month) addTo(income, i.currency, i.memberId, i.amount);
  }
  return MonthSummary(
    sharedTotal: sharedTotal,
    sharedByCategory: byCat,
    paidShared: paid,
    shareOfShared: share,
    personal: personal,
    income: income,
  );
}

enum BudgetLevel { ok, warning, exceeded }

class BudgetStatus {
  final Budget budget;
  final int spent;
  const BudgetStatus(this.budget, this.spent);

  double get ratio => budget.limit == 0 ? 0 : spent / budget.limit;
  int get remaining => budget.limit - spent;

  /// Aviso a partir del 80% del tope.
  BudgetLevel get level => ratio > 1
      ? BudgetLevel.exceeded
      : ratio >= 0.8
          ? BudgetLevel.warning
          : BudgetLevel.ok;
}

List<BudgetStatus> budgetStatuses(Iterable<Budget> budgets, MonthSummary s) => [
      for (final b in budgets)
        BudgetStatus(b, s.sharedByCategory[b.currency]?[b.category] ?? 0),
    ];

/// Si un gasto es visible para todo el hogar o solo para quien lo pagó.
/// Se guarda en cada documento (campo `public`) para que las reglas de
/// seguridad de Firestore apliquen la privacidad del lado del servidor, no
/// solo en la app.
bool isPublic(ExpenseBase e, Member? owner) {
  if (e.isShared) return true;
  return switch (owner?.privacy ?? PrivacyMode.allVisible) {
    PrivacyMode.allVisible => true,
    PrivacyMode.sharedOnly => false,
    PrivacyMode.perExpense => e.visibleToPartner,
  };
}

/// Si [viewerId] puede ver el gasto según la privacidad del dueño.
bool isVisibleTo(ExpenseBase e, String viewerId, Household h) =>
    e.paidBy == viewerId || isPublic(e, h.member(e.paidBy));
