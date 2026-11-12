import 'dart:async';

import 'package:flutter/widgets.dart';

import 'data/repository.dart';
import 'logic/finance.dart';
import 'logic/plan.dart';
import 'models/models.dart';

/// Datos del hogar en vivo. Se suscribe a todas las colecciones y avisa a
/// la UI cuando algo cambia (incluidos los cambios que hace la pareja).
class HouseholdState extends ChangeNotifier {
  HouseholdState(this.repo, this.user) {
    final hid = user.householdId!;
    // Los errores de escucha los reintenta el repositorio; acá solo se evita
    // que un error suelto tire abajo la app.
    void ignore(Object _) {}
    _subs.addAll([
      repo.watchHousehold(hid).listen(_onHousehold, onError: ignore),
      repo.watchExpenses(hid).listen((v) => _set(() => expenses = v), onError: ignore),
      repo.watchRecurring(hid).listen((v) => _set(() => recurring = v), onError: ignore),
      repo.watchIncomes(hid).listen((v) => _set(() => incomes = v), onError: ignore),
      repo.watchSettlements(hid).listen((v) => _set(() => settlements = v), onError: ignore),
      repo.watchBudgets(hid).listen((v) => _set(() => budgets = v), onError: ignore),
    ]);
  }

  final Repository repo;

  /// Se actualiza cuando cambian sus preferencias o su lista de hogares.
  AppUser user;
  final _subs = <StreamSubscription>[];

  Household? household;
  List<Expense> expenses = [];
  List<RecurringExpense> recurring = [];
  List<Income> incomes = [];
  List<Settlement> settlements = [];
  List<Budget> budgets = [];

  /// Mes que se está mirando en las pantallas.
  YearMonth month = YearMonth.now();

  /// Refresca las pantallas si cambiaron las preferencias o los hogares.
  void updateUser(AppUser u) {
    if (identical(u, user)) return;
    user = u;
    scheduleMicrotask(() => _set(() {}));
  }

  bool _wiping = false;
  String? _wipeDone;
  bool _disposed = false;

  void _onHousehold(Household h) {
    _set(() => household = h);
    // Mantiene al día el nombre del hogar guardado en la cuenta.
    if (user.households[h.id] != h.name) {
      repo.switchHousehold(h.id, name: h.name).catchError((_) {});
    }
    _runApprovedWipe(h);
  }

  /// Cuando el borrado fue aceptado, cada app borra lo que le corresponde.
  /// Quien lo pidió, además, cierra el pedido.
  Future<void> _runApprovedWipe(Household h) async {
    final w = h.wipe;
    if (w == null) {
      _wipeDone = null;
      return;
    }
    // Cada pedido aprobado se procesa una sola vez en esta app.
    final key = '${w.requestedBy}/${w.scope.name}/${w.approvedBy}';
    if (!w.approved || _wiping || _wipeDone == key) return;
    _wiping = true;
    try {
      await repo.wipeData(h.id, w.scope);
      _wipeDone = key;
      if (w.requestedBy == me) await repo.setWipe(h.id, null);
    } catch (_) {
      // Se reintenta la próxima vez que llegue el hogar.
    } finally {
      _wiping = false;
    }
  }

  /// Pide borrar los datos. Si no hay pareja en el hogar, borra directamente.
  Future<void> requestWipe(WipeScope scope) async {
    if (partner == null) return repo.wipeData(hid, scope);
    await repo.setWipe(hid, WipeRequest(requestedBy: me, scope: scope));
  }

  Future<void> approveWipe() async {
    final w = household?.wipe;
    if (w == null || w.requestedBy == me) return;
    await repo.setWipe(
        hid, WipeRequest(requestedBy: w.requestedBy, scope: w.scope, approvedBy: me));
  }

  Future<void> cancelWipe() => repo.setWipe(hid, null);

  List<Currency> get currencies => household?.currencies ?? defaultCurrencies;
  Currency get mainCurrency => currencies.first;
  Entitlements get entitlements => Entitlements.of(household);

  String get hid => user.householdId!;
  String get me => user.id;
  Member? get partner => household?.partnerOf(me);
  List<String> get memberIds => household?.members.map((m) => m.id).toList() ?? [me];

  String nameOf(String id) =>
      id == me ? 'Vos' : household?.member(id)?.name ?? 'Tu pareja';

  void setMonth(YearMonth m) => _set(() => month = m);

  void _set(VoidCallback f) {
    if (_disposed) return;
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
    _disposed = true;
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
  const RepoScope({
    super.key,
    required this.repo,
    required this.demo,
    this.user,
    required super.child,
  });
  final Repository repo;
  final bool demo;

  /// Usuario logueado (null en la pantalla de login).
  final AppUser? user;

  static RepoScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RepoScope>()!;

  @override
  bool updateShouldNotify(RepoScope old) => old.repo != repo || old.user != user;
}
