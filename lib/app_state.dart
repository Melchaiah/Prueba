import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data/repository.dart';
import 'logic/finance.dart';
import 'models/models.dart';

/// Datos del hogar en vivo. Se suscribe a todas las colecciones y avisa a
/// la UI cuando algo cambia (incluidos los cambios que hace la pareja).
class HouseholdState extends ChangeNotifier {
  HouseholdState(this.repo, this.user) {
    final hid = user.householdId!;
    _subs.addAll([
      repo.watchHousehold(hid).listen((v) => _set(() => household = v)),
      repo.watchExpenses(hid).listen((v) => _set(() => expenses = v)),
      repo.watchRecurring(hid).listen((v) => _set(() => recurring = v)),
      repo.watchIncomes(hid).listen((v) => _set(() => incomes = v)),
      repo.watchSettlements(hid).listen((v) => _set(() => settlements = v)),
      repo.watchBudgets(hid).listen((v) => _set(() => budgets = v)),
    ]);
  }

  final Repository repo;
  final AppUser user;
  final _subs = <StreamSubscription>[];

  Household? household;
  List<Expense> expenses = [];
  List<RecurringExpense> recurring = [];
  List<Income> incomes = [];
  List<Settlement> settlements = [];
  List<Budget> budgets = [];

  /// Mes que se está mirando en las pantallas.
  YearMonth month = YearMonth.now();

  String get hid => user.householdId!;
  String get me => user.id;
  Member? get partner => household?.partnerOf(me);
  List<String> get memberIds => household?.members.map((m) => m.id).toList() ?? [me];

  String nameOf(String id) =>
      id == me ? 'Vos' : household?.member(id)?.name ?? 'Tu pareja';

  void setMonth(YearMonth m) => _set(() => month = m);

  void _set(VoidCallback f) {
    f();
    notifyListeners();
  }

  List<Charge> get monthCharges => chargesForMonth(month, expenses, recurring);

  MonthSummary get summary =>
      summarizeMonth(month: month, charges: monthCharges, incomes: incomes);

  /// Saldo acumulado hasta el mes actual (las cuotas futuras no cuentan).
  Map<Currency, Map<String, int>> get balances => computeBalances(
        memberIds: memberIds,
        charges: chargesUpTo(YearMonth.now(), expenses, recurring),
        settlements: settlements,
      );

  Shares proportional(Currency c) =>
      proportionalSplit(memberIds, incomes, month, currency: c);

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Da acceso a [HouseholdState] desde cualquier pantalla.
class HouseholdScope extends InheritedNotifier<HouseholdState> {
  const HouseholdScope({super.key, required HouseholdState state, required super.child})
      : super(notifier: state);

  static HouseholdState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HouseholdScope>()!.notifier!;
}

/// Da acceso al repositorio (y a si estamos en modo demo).
class RepoScope extends InheritedWidget {
  const RepoScope({super.key, required this.repo, required this.demo, required super.child});
  final Repository repo;
  final bool demo;

  static RepoScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepoScope>()!;

  @override
  bool updateShouldNotify(RepoScope old) => old.repo != repo;
}
