// Modelo de datos de la app.
//
// Todos los montos se guardan en centavos (int) para evitar errores de
// redondeo con double. Los meses se representan con [YearMonth].

enum Currency {
  ars('ARS', r'$', 'Peso argentino'),
  usd('USD', r'US$', 'Dólar estadounidense'),
  eur('EUR', '€', 'Euro'),
  brl('BRL', r'R$', 'Real brasileño'),
  uyu('UYU', r'$U', 'Peso uruguayo'),
  clp('CLP', r'CLP$', 'Peso chileno'),
  mxn('MXN', r'MX$', 'Peso mexicano');

  const Currency(this.code, this.symbol, this.label);
  final String code;
  final String symbol;
  final String label;

  static Currency parse(String? s) =>
      values.firstWhere((c) => c.code == s, orElse: () => ars);
}

/// Monedas que usa un hogar si no eligió otras.
const defaultCurrencies = [Currency.ars, Currency.usd];

enum ThemePref { system, light, dark }

/// Preferencias personales (se guardan con la cuenta, no con el hogar).
class UserPrefs {
  final ThemePref theme;

  /// Índice en la lista de paletas de `theme.dart`.
  final int palette;

  /// Mostrar y cargar centavos.
  final bool showDecimals;

  const UserPrefs({
    this.theme = ThemePref.system,
    this.palette = 0,
    this.showDecimals = true,
  });

  UserPrefs copyWith({ThemePref? theme, int? palette, bool? showDecimals}) => UserPrefs(
        theme: theme ?? this.theme,
        palette: palette ?? this.palette,
        showDecimals: showDecimals ?? this.showDecimals,
      );

  Map<String, dynamic> toMap() =>
      {'theme': theme.name, 'palette': palette, 'showDecimals': showDecimals};

  factory UserPrefs.fromMap(Map? m) => UserPrefs(
        theme: ThemePref.values.firstWhere((t) => t.name == m?['theme'],
            orElse: () => ThemePref.system),
        palette: (m?['palette'] as num?)?.toInt() ?? 0,
        showDecimals: m?['showDecimals'] as bool? ?? true,
      );
}

/// Qué se borra al reiniciar los datos de un hogar.
enum WipeScope {
  /// Gastos, ingresos y pagos. Quedan los gastos fijos y presupuestos.
  movements,

  /// Todo: también gastos fijos y presupuestos.
  all,
}

/// Pedido de borrado de datos. Con dos personas en el hogar, una lo pide y
/// la otra lo tiene que aceptar.
class WipeRequest {
  final String requestedBy;
  final WipeScope scope;
  final String? approvedBy;
  const WipeRequest({required this.requestedBy, required this.scope, this.approvedBy});

  bool get approved => approvedBy != null;

  Map<String, dynamic> toMap() =>
      {'requestedBy': requestedBy, 'scope': scope.name, 'approvedBy': approvedBy};

  static WipeRequest? fromMap(Map? m) => m == null || m['requestedBy'] == null
      ? null
      : WipeRequest(
          requestedBy: m['requestedBy'] as String,
          scope: WipeScope.values
              .firstWhere((x) => x.name == m['scope'], orElse: () => WipeScope.movements),
          approvedBy: m['approvedBy'] as String?,
        );
}

/// Qué ve tu pareja de tus gastos personales. Lo elige cada persona.
enum PrivacyMode {
  /// Tu pareja ve todos tus gastos personales.
  allVisible,

  /// Tu pareja solo ve los gastos compartidos.
  sharedOnly,

  /// Al cargar cada gasto personal elegís si es visible o privado.
  perExpense,
}

extension PrivacyModeX on PrivacyMode {
  String get title => switch (this) {
        PrivacyMode.allVisible => 'Todo visible',
        PrivacyMode.sharedOnly => 'Solo compartidos',
        PrivacyMode.perExpense => 'Elegir en cada gasto',
      };
  String get description => switch (this) {
        PrivacyMode.allVisible =>
          'Tu pareja ve todos tus gastos, también los personales.',
        PrivacyMode.sharedOnly =>
          'Tus gastos personales son privados. Tu pareja solo ve los compartidos.',
        PrivacyMode.perExpense =>
          'Cada vez que cargás un gasto personal elegís si es visible o privado.',
      };
  static PrivacyMode parse(String? s) => PrivacyMode.values
      .firstWhere((m) => m.name == s, orElse: () => PrivacyMode.allVisible);
}

class YearMonth implements Comparable<YearMonth> {
  final int year;
  final int month; // 1..12
  const YearMonth(this.year, this.month);

  factory YearMonth.fromDate(DateTime d) => YearMonth(d.year, d.month);
  factory YearMonth.now() => YearMonth.fromDate(DateTime.now());

  /// Índice absoluto de meses, útil para restar meses.
  int get index => year * 12 + (month - 1);
  factory YearMonth.fromIndex(int i) => YearMonth(i ~/ 12, i % 12 + 1);

  YearMonth add(int months) => YearMonth.fromIndex(index + months);
  int monthsSince(YearMonth other) => index - other.index;

  @override
  int compareTo(YearMonth other) => index.compareTo(other.index);
  bool operator <(YearMonth o) => index < o.index;
  bool operator <=(YearMonth o) => index <= o.index;
  bool operator >(YearMonth o) => index > o.index;
  bool operator >=(YearMonth o) => index >= o.index;

  @override
  bool operator ==(Object other) =>
      other is YearMonth && other.index == index;
  @override
  int get hashCode => index;

  /// Formato `2026-11`, ordenable como texto (se usa en Firestore).
  String get key => '$year-${month.toString().padLeft(2, '0')}';
  static YearMonth parse(String key) {
    final p = key.split('-');
    return YearMonth(int.parse(p[0]), int.parse(p[1]));
  }

  @override
  String toString() => key;
}

class Member {
  final String id;
  final String name;
  final PrivacyMode privacy;
  const Member({required this.id, required this.name, this.privacy = PrivacyMode.allVisible});

  Member copyWith({String? name, PrivacyMode? privacy}) =>
      Member(id: id, name: name ?? this.name, privacy: privacy ?? this.privacy);

  Map<String, dynamic> toMap() => {'name': name, 'privacy': privacy.name};
  factory Member.fromMap(String id, Map<String, dynamic> m) => Member(
        id: id,
        name: m['name'] as String? ?? 'Sin nombre',
        privacy: PrivacyModeX.parse(m['privacy'] as String?),
      );
}

class Household {
  final String id;
  final String name;
  final List<Member> members;
  final String? inviteCode;

  /// Monedas habilitadas; la primera es la principal.
  final List<Currency> currencies;
  final WipeRequest? wipe;

  /// Plan del hogar ('free', 'premium'). Solo lo escribe el servidor.
  final String plan;

  const Household({
    required this.id,
    required this.name,
    required this.members,
    this.inviteCode,
    this.currencies = defaultCurrencies,
    this.wipe,
    this.plan = 'free',
  });

  Household copyWith({
    List<Member>? members,
    List<Currency>? currencies,
    WipeRequest? Function()? wipe,
  }) =>
      Household(
        id: id,
        name: name,
        inviteCode: inviteCode,
        plan: plan,
        members: members ?? this.members,
        currencies: currencies ?? this.currencies,
        wipe: wipe != null ? wipe() : this.wipe,
      );

  Member? member(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Member? partnerOf(String id) {
    for (final m in members) {
      if (m.id != id) return m;
    }
    return null;
  }
}

const defaultCategories = <String>[
  'Supermercado',
  'Alquiler / Expensas',
  'Servicios',
  'Transporte',
  'Salidas',
  'Salud',
  'Ropa',
  'Hogar',
  'Suscripciones',
  'Educación',
  'Regalos',
  'Otros',
];

/// Cómo se reparte un gasto compartido: miembro -> porcentaje (suma 100).
typedef Shares = Map<String, double>;

/// Campos comunes a un gasto puntual y a uno recurrente.
abstract class ExpenseBase {
  String get id;
  String get description;
  String get category;
  Currency get currency;
  String get paidBy;
  bool get isShared;
  Shares get split;
  bool get visibleToPartner;
}

class Expense implements ExpenseBase {
  @override
  final String id;
  @override
  final String description;
  @override
  final String category;

  /// Monto total en centavos (si es en cuotas, el total de todas).
  final int amount;
  @override
  final Currency currency;
  final DateTime date;
  @override
  final String paidBy;
  @override
  final bool isShared;
  @override
  final Shares split;

  /// Cantidad de cuotas (1 = pago único). Cada cuota cae en un mes, a
  /// partir de [firstInstallment].
  final int installments;
  final YearMonth firstInstallment;
  @override
  final bool visibleToPartner;

  const Expense({
    required this.id,
    required this.description,
    required this.category,
    required this.amount,
    required this.currency,
    required this.date,
    required this.paidBy,
    required this.isShared,
    required this.split,
    this.installments = 1,
    required this.firstInstallment,
    this.visibleToPartner = true,
  });

  YearMonth get lastInstallment => firstInstallment.add(installments - 1);

  Map<String, dynamic> toMap() => {
        'description': description,
        'category': category,
        'amount': amount,
        'currency': currency.code,
        'date': date.millisecondsSinceEpoch,
        'paidBy': paidBy,
        'isShared': isShared,
        'split': split,
        'installments': installments,
        'firstInstallment': firstInstallment.key,
        'lastInstallment': lastInstallment.key,
        'visibleToPartner': visibleToPartner,
      };

  factory Expense.fromMap(String id, Map<String, dynamic> m) => Expense(
        id: id,
        description: m['description'] as String? ?? '',
        category: m['category'] as String? ?? 'Otros',
        amount: (m['amount'] as num).toInt(),
        currency: Currency.parse(m['currency'] as String?),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
        paidBy: m['paidBy'] as String,
        isShared: m['isShared'] as bool? ?? true,
        split: _splitFrom(m['split']),
        installments: (m['installments'] as num?)?.toInt() ?? 1,
        firstInstallment: YearMonth.parse(m['firstInstallment'] as String),
        visibleToPartner: m['visibleToPartner'] as bool? ?? true,
      );
}

class RecurringExpense implements ExpenseBase {
  @override
  final String id;
  @override
  final String description;
  @override
  final String category;

  /// Monto mensual en centavos.
  final int amount;
  @override
  final Currency currency;
  @override
  final String paidBy;
  @override
  final bool isShared;
  @override
  final Shares split;
  final int dayOfMonth;
  final YearMonth start;

  /// Último mes incluido; null = sigue vigente.
  final YearMonth? end;
  @override
  final bool visibleToPartner;

  /// Ajustes para meses puntuales: mes -> monto en centavos. Un monto 0
  /// significa que ese mes no se paga. Los meses sin ajuste usan [amount].
  final Map<YearMonth, int> overrides;

  const RecurringExpense({
    required this.id,
    required this.description,
    required this.category,
    required this.amount,
    required this.currency,
    required this.paidBy,
    required this.isShared,
    required this.split,
    this.dayOfMonth = 1,
    required this.start,
    this.end,
    this.visibleToPartner = true,
    this.overrides = const {},
  });

  bool activeIn(YearMonth m) => m >= start && (end == null || m <= end!);

  /// Monto que corresponde a [m]: el ajustado si lo hay, o el habitual.
  int amountIn(YearMonth m) => overrides[m] ?? amount;

  /// Copia con el monto de [m] ajustado; con [value] null vuelve al habitual.
  RecurringExpense withOverride(YearMonth m, int? value) {
    final next = Map.of(overrides);
    if (value == null || value == amount) {
      next.remove(m);
    } else {
      next[m] = value;
    }
    return copyWith(overrides: next);
  }

  RecurringExpense copyWith({YearMonth? Function()? end, Map<YearMonth, int>? overrides}) =>
      RecurringExpense(
        id: id,
        description: description,
        category: category,
        amount: amount,
        currency: currency,
        paidBy: paidBy,
        isShared: isShared,
        split: split,
        dayOfMonth: dayOfMonth,
        start: start,
        end: end != null ? end() : this.end,
        visibleToPartner: visibleToPartner,
        overrides: overrides ?? this.overrides,
      );

  Map<String, dynamic> toMap() => {
        'description': description,
        'category': category,
        'amount': amount,
        'currency': currency.code,
        'paidBy': paidBy,
        'isShared': isShared,
        'split': split,
        'dayOfMonth': dayOfMonth,
        'start': start.key,
        'end': end?.key,
        'visibleToPartner': visibleToPartner,
        'overrides': {for (final e in overrides.entries) e.key.key: e.value},
      };

  factory RecurringExpense.fromMap(String id, Map<String, dynamic> m) =>
      RecurringExpense(
        id: id,
        description: m['description'] as String? ?? '',
        category: m['category'] as String? ?? 'Otros',
        amount: (m['amount'] as num).toInt(),
        currency: Currency.parse(m['currency'] as String?),
        paidBy: m['paidBy'] as String,
        isShared: m['isShared'] as bool? ?? true,
        split: _splitFrom(m['split']),
        dayOfMonth: (m['dayOfMonth'] as num?)?.toInt() ?? 1,
        start: YearMonth.parse(m['start'] as String),
        end: m['end'] == null ? null : YearMonth.parse(m['end'] as String),
        visibleToPartner: m['visibleToPartner'] as bool? ?? true,
        overrides: {
          for (final e in (m['overrides'] as Map? ?? {}).entries)
            YearMonth.parse(e.key as String): (e.value as num).toInt(),
        },
      );
}

class Income {
  final String id;
  final String memberId;
  final String description;
  final int amount; // centavos
  final Currency currency;
  final YearMonth month;

  const Income({
    required this.id,
    required this.memberId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.month,
  });

  Map<String, dynamic> toMap() => {
        'memberId': memberId,
        'description': description,
        'amount': amount,
        'currency': currency.code,
        'month': month.key,
      };

  factory Income.fromMap(String id, Map<String, dynamic> m) => Income(
        id: id,
        memberId: m['memberId'] as String,
        description: m['description'] as String? ?? 'Sueldo',
        amount: (m['amount'] as num).toInt(),
        currency: Currency.parse(m['currency'] as String?),
        month: YearMonth.parse(m['month'] as String),
      );
}

/// Pago entre la pareja para saldar deudas.
class Settlement {
  final String id;
  final String from;
  final String to;
  final int amount; // centavos
  final Currency currency;
  final DateTime date;

  const Settlement({
    required this.id,
    required this.from,
    required this.to,
    required this.amount,
    required this.currency,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'from': from,
        'to': to,
        'amount': amount,
        'currency': currency.code,
        'date': date.millisecondsSinceEpoch,
      };

  factory Settlement.fromMap(String id, Map<String, dynamic> m) => Settlement(
        id: id,
        from: m['from'] as String,
        to: m['to'] as String,
        amount: (m['amount'] as num).toInt(),
        currency: Currency.parse(m['currency'] as String?),
        date: DateTime.fromMillisecondsSinceEpoch((m['date'] as num).toInt()),
      );
}

/// Tope mensual de gasto compartido para una categoría.
class Budget {
  final String id;
  final String category;
  final int limit; // centavos
  final Currency currency;

  const Budget({required this.id, required this.category, required this.limit, required this.currency});

  Map<String, dynamic> toMap() =>
      {'category': category, 'limit': limit, 'currency': currency.code};

  factory Budget.fromMap(String id, Map<String, dynamic> m) => Budget(
        id: id,
        category: m['category'] as String,
        limit: (m['limit'] as num).toInt(),
        currency: Currency.parse(m['currency'] as String?),
      );
}

Shares _splitFrom(dynamic raw) {
  if (raw is! Map) return {};
  return raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
}
