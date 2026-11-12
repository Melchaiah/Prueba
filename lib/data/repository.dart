import '../models/models.dart';

/// Usuario logueado.
class AppUser {
  final String id;
  final String name;
  final String? householdId;
  const AppUser({required this.id, required this.name, this.householdId});
}

/// Acceso a datos. Hay una implementación con Firebase y otra en memoria
/// (modo demo y tests).
abstract class Repository {
  // --- Sesión ---
  Stream<AppUser?> watchUser();
  Future<void> signIn(String email, String password);
  Future<void> register(String name, String email, String password);
  Future<void> signOut();

  // --- Hogar ---
  /// Crea el hogar y devuelve el código de invitación para la pareja.
  Future<String> createHousehold(String name);
  Future<void> joinHousehold(String inviteCode);
  Stream<Household> watchHousehold(String householdId);
  Future<void> setPrivacy(String householdId, PrivacyMode mode);

  // --- Movimientos (solo lo que el usuario actual puede ver) ---
  Stream<List<Expense>> watchExpenses(String householdId);
  Stream<List<RecurringExpense>> watchRecurring(String householdId);
  Stream<List<Income>> watchIncomes(String householdId);
  Stream<List<Settlement>> watchSettlements(String householdId);
  Stream<List<Budget>> watchBudgets(String householdId);

  Future<void> saveExpense(String householdId, Expense e);
  Future<void> deleteExpense(String householdId, String id);
  Future<void> saveRecurring(String householdId, RecurringExpense r);
  Future<void> deleteRecurring(String householdId, String id);
  Future<void> saveIncome(String householdId, Income i);
  Future<void> deleteIncome(String householdId, String id);
  Future<void> saveSettlement(String householdId, Settlement s);
  Future<void> saveBudget(String householdId, Budget b);
  Future<void> deleteBudget(String householdId, String id);

  /// Genera un id nuevo para un documento.
  String newId();
}
