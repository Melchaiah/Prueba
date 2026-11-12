import 'dart:async';
import 'dart:math';

import '../logic/finance.dart';
import '../models/models.dart';
import 'repository.dart';

/// Repositorio en memoria. Sirve para probar la app sin configurar Firebase
/// (modo demo) y para los tests. Los datos se pierden al cerrar la app.
class MemoryRepository implements Repository {
  MemoryRepository({bool withDemoData = false}) {
    if (withDemoData) _seedDemo();
  }

  final _rand = Random();
  final _changes = StreamController<void>.broadcast();

  AppUser? _user;
  final Map<String, Household> _households = {};
  final Map<String, String> _invites = {}; // código -> householdId
  final Map<String, Map<String, Expense>> _expenses = {};
  final Map<String, Map<String, RecurringExpense>> _recurring = {};
  final Map<String, Map<String, Income>> _incomes = {};
  final Map<String, Map<String, Settlement>> _settlements = {};
  final Map<String, Map<String, Budget>> _budgets = {};

  /// Emite el valor actual y lo vuelve a emitir con cada cambio.
  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  void _notify() => _changes.add(null);

  @override
  String newId() =>
      List.generate(20, (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_rand.nextInt(36)]).join();

  // --- Sesión ---
  @override
  Stream<AppUser?> watchUser() => _watch(() => _user);

  @override
  Future<void> signIn(String email, String password) async {
    _user = AppUser(id: newId(), name: email.split('@').first);
    _notify();
  }

  @override
  Future<void> register(String name, String email, String password) async {
    _user = AppUser(id: newId(), name: name);
    _notify();
  }

  @override
  Future<void> signOut() async {
    _user = null;
    _notify();
  }

  /// Cambia de usuario en el modo demo, para ver la app como la pareja.
  void switchToPartner() {
    final u = _user;
    if (u?.householdId == null) return;
    final partner = _households[u!.householdId]!.partnerOf(u.id);
    if (partner == null) return;
    _user = AppUser(id: partner.id, name: partner.name, householdId: u.householdId);
    _notify();
  }

  // --- Hogar ---
  @override
  Future<String> createHousehold(String name) async {
    final u = _user!;
    final id = newId();
    final code = _code();
    _households[id] = Household(
      id: id,
      name: name,
      members: [Member(id: u.id, name: u.name)],
      inviteCode: code,
    );
    _invites[code] = id;
    _user = AppUser(id: u.id, name: u.name, householdId: id);
    _notify();
    return code;
  }

  @override
  Future<void> joinHousehold(String inviteCode) async {
    final u = _user!;
    final id = _invites.remove(inviteCode.trim().toUpperCase());
    if (id == null) throw StateError('Código de invitación inválido');
    final h = _households[id]!;
    if (h.members.length >= 2) throw StateError('El hogar ya está completo');
    _households[id] = Household(
      id: id,
      name: h.name,
      members: [...h.members, Member(id: u.id, name: u.name)],
    );
    _user = AppUser(id: u.id, name: u.name, householdId: id);
    _notify();
  }

  @override
  Stream<Household> watchHousehold(String householdId) =>
      _watch(() => _households[householdId]!);

  @override
  Future<void> setPrivacy(String householdId, PrivacyMode mode) async {
    final h = _households[householdId]!;
    _households[householdId] = Household(
      id: h.id,
      name: h.name,
      inviteCode: h.inviteCode,
      members: [
        for (final m in h.members) m.id == _user!.id ? m.copyWith(privacy: mode) : m,
      ],
    );
    _notify();
  }

  // --- Movimientos ---
  bool _visible(String hid, ExpenseBase e) =>
      isVisibleTo(e, _user!.id, _households[hid]!);

  @override
  Stream<List<Expense>> watchExpenses(String hid) => _watch(() =>
      (_expenses[hid]?.values ?? const <Expense>[]).where((e) => _visible(hid, e)).toList()
        ..sort((a, b) => b.date.compareTo(a.date)));

  @override
  Stream<List<RecurringExpense>> watchRecurring(String hid) => _watch(() =>
      (_recurring[hid]?.values ?? const <RecurringExpense>[])
          .where((e) => _visible(hid, e))
          .toList());

  @override
  Stream<List<Income>> watchIncomes(String hid) =>
      _watch(() => (_incomes[hid]?.values ?? const <Income>[]).toList());

  @override
  Stream<List<Settlement>> watchSettlements(String hid) =>
      _watch(() => (_settlements[hid]?.values ?? const <Settlement>[]).toList());

  @override
  Stream<List<Budget>> watchBudgets(String hid) =>
      _watch(() => (_budgets[hid]?.values ?? const <Budget>[]).toList());

  Future<void> _put<T>(Map<String, Map<String, T>> m, String hid, String id, T v) async {
    m.putIfAbsent(hid, () => {})[id] = v;
    _notify();
  }

  Future<void> _del<T>(Map<String, Map<String, T>> m, String hid, String id) async {
    m[hid]?.remove(id);
    _notify();
  }

  @override
  Future<void> saveExpense(String hid, Expense e) => _put(_expenses, hid, e.id, e);
  @override
  Future<void> deleteExpense(String hid, String id) => _del(_expenses, hid, id);
  @override
  Future<void> saveRecurring(String hid, RecurringExpense r) => _put(_recurring, hid, r.id, r);
  @override
  Future<void> deleteRecurring(String hid, String id) => _del(_recurring, hid, id);
  @override
  Future<void> saveIncome(String hid, Income i) => _put(_incomes, hid, i.id, i);
  @override
  Future<void> deleteIncome(String hid, String id) => _del(_incomes, hid, id);
  @override
  Future<void> saveSettlement(String hid, Settlement s) => _put(_settlements, hid, s.id, s);
  @override
  Future<void> saveBudget(String hid, Budget b) => _put(_budgets, hid, b.id, b);
  @override
  Future<void> deleteBudget(String hid, String id) => _del(_budgets, hid, id);

  String _code() => List.generate(
      6, (_) => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[_rand.nextInt(32)]).join();

  /// Datos de ejemplo: una pareja con sueldos distintos y algunos gastos.
  void _seedDemo() {
    const hid = 'demo';
    const a = 'ana', b = 'juan';
    final now = YearMonth.now();
    final today = DateTime.now();
    _user = const AppUser(id: a, name: 'Ana', householdId: hid);
    _households[hid] = const Household(id: hid, name: 'Casa', members: [
      Member(id: a, name: 'Ana'),
      Member(id: b, name: 'Juan', privacy: PrivacyMode.perExpense),
    ]);
    _incomes[hid] = {
      'i1': Income(id: 'i1', memberId: a, description: 'Sueldo', amount: 180000000, currency: Currency.ars, month: now),
      'i2': Income(id: 'i2', memberId: b, description: 'Sueldo', amount: 120000000, currency: Currency.ars, month: now),
    };
    const prop = {a: 60.0, b: 40.0};
    const half = {a: 50.0, b: 50.0};
    _recurring[hid] = {
      'r1': RecurringExpense(id: 'r1', description: 'Alquiler', category: 'Alquiler / Expensas', amount: 65000000, currency: Currency.ars, paidBy: a, isShared: true, split: prop, dayOfMonth: 5, start: now.add(-2)),
      'r2': RecurringExpense(id: 'r2', description: 'Streaming', category: 'Suscripciones', amount: 1200, currency: Currency.usd, paidBy: b, isShared: true, split: half, start: now.add(-2)),
    };
    _expenses[hid] = {
      'e1': Expense(id: 'e1', description: 'Supermercado semanal', category: 'Supermercado', amount: 8550000, currency: Currency.ars, date: today, paidBy: b, isShared: true, split: prop, firstInstallment: now),
      'e2': Expense(id: 'e2', description: 'Heladera', category: 'Hogar', amount: 120000000, currency: Currency.ars, date: today.subtract(const Duration(days: 40)), paidBy: a, isShared: true, split: half, installments: 6, firstInstallment: now.add(-1)),
      'e3': Expense(id: 'e3', description: 'Cena', category: 'Salidas', amount: 4200000, currency: Currency.ars, date: today.subtract(const Duration(days: 3)), paidBy: b, isShared: true, split: half, firstInstallment: now),
      'e4': Expense(id: 'e4', description: 'Zapatillas', category: 'Ropa', amount: 15000000, currency: Currency.ars, date: today.subtract(const Duration(days: 2)), paidBy: a, isShared: false, split: const {a: 100}, firstInstallment: now),
      'e5': Expense(id: 'e5', description: 'Regalo sorpresa', category: 'Regalos', amount: 3000000, currency: Currency.ars, date: today.subtract(const Duration(days: 1)), paidBy: b, isShared: false, split: const {b: 100}, firstInstallment: now, visibleToPartner: false),
    };
    _budgets[hid] = {
      'b1': const Budget(id: 'b1', category: 'Supermercado', limit: 40000000, currency: Currency.ars),
      'b2': const Budget(id: 'b2', category: 'Salidas', limit: 5000000, currency: Currency.ars),
    };
  }
}
