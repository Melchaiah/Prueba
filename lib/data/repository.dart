import '../models/models.dart';

/// Usuario logueado.
class AppUser {
  final String id;
  final String name;

  /// Hogar que está mirando ahora.
  final String? householdId;

  /// Todos sus hogares: id -> nombre.
  final Map<String, String> households;
  final UserPrefs prefs;

  const AppUser({
    required this.id,
    required this.name,
    this.householdId,
    this.households = const {},
    this.prefs = const UserPrefs(),
  });
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
  Future<void> setCurrencies(String householdId, List<Currency> currencies);

  /// Cambia el hogar que se está mirando. Con [id] null vuelve a la pantalla
  /// de crear/unirse. [name] actualiza el nombre guardado en la cuenta.
  Future<void> switchHousehold(String? id, {String? name});
  Future<void> savePrefs(UserPrefs prefs);

  // --- Borrado de datos ---
  /// Guarda (o quita, con null) el pedido de borrado del hogar.
  Future<void> setWipe(String householdId, WipeRequest? wipe);

  /// Borra todo lo que el usuario actual puede borrar: lo compartido y lo
  /// propio. Lo personal de la pareja lo borra su app.
  Future<void> wipeData(String householdId, WipeScope scope);

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
