import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/app_state.dart';
import 'package:gastos_pareja/data/memory_repository.dart';
import 'package:gastos_pareja/data/repository.dart';
import 'package:gastos_pareja/models/models.dart';

Future<AppUser> currentUser(MemoryRepository repo) async => (await repo.watchUser().first)!;

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('varios hogares: crear otro, cambiar y volver', () async {
    final repo = MemoryRepository(withDemoData: true);
    var u = await currentUser(repo);
    expect(u.households, {'demo': 'Casa'});

    await repo.createHousehold('Depto de la playa');
    u = await currentUser(repo);
    expect(u.households.length, 2);
    expect(u.householdId, isNot('demo'));
    expect(await repo.watchExpenses(u.householdId!).first, isEmpty);

    await repo.switchHousehold('demo');
    u = await currentUser(repo);
    expect(u.householdId, 'demo');
    expect(await repo.watchExpenses('demo').first, isNotEmpty);
  });

  test('monedas del hogar y preferencias personales', () async {
    final repo = MemoryRepository(withDemoData: true);
    await repo.setCurrencies('demo', [Currency.eur, Currency.ars]);
    expect((await repo.watchHousehold('demo').first).currencies.first, Currency.eur);

    await repo.savePrefs(const UserPrefs(theme: ThemePref.dark, showDecimals: false));
    expect((await currentUser(repo)).prefs.theme, ThemePref.dark);
    // Las preferencias son de cada persona.
    repo.switchToPartner();
    expect((await currentUser(repo)).prefs.theme, ThemePref.system);
  });

  test('borrado de datos: hace falta que la pareja acepte', () async {
    final repo = MemoryRepository(withDemoData: true);
    var ana = HouseholdState(repo, await currentUser(repo));
    await settle();

    await ana.requestWipe(WipeScope.movements);
    await settle();
    // Pedido pendiente: todavía no se borró nada.
    expect(ana.household!.wipe!.approved, isFalse);
    expect(ana.expenses, isNotEmpty);
    // Quien lo pidió no lo puede aprobar.
    await ana.approveWipe();
    await settle();
    expect(ana.household!.wipe!.approved, isFalse);
    ana.dispose();

    // Juan acepta: su app borra lo compartido y lo suyo.
    repo.switchToPartner();
    final juan = HouseholdState(repo, await currentUser(repo));
    await settle();
    await juan.approveWipe();
    await settle();
    // Solo queda el gasto personal de Ana: ese lo borra la app de ella.
    expect(juan.expenses.every((e) => !e.isShared && e.paidBy == 'ana'), isTrue);
    expect(juan.expenses.length, 1);
    expect(juan.incomes, isEmpty);
    expect(juan.recurring, isNotEmpty, reason: 'los gastos fijos quedan');
    juan.dispose();

    // La app de Ana borra sus gastos personales y cierra el pedido.
    repo.switchToPartner();
    ana = HouseholdState(repo, await currentUser(repo));
    await settle();
    expect(ana.expenses, isEmpty);
    expect(ana.household!.wipe, isNull);
    expect(ana.budgets, isNotEmpty);
    ana.dispose();
  });

  test('borrado total rechazado no borra nada', () async {
    final repo = MemoryRepository(withDemoData: true);
    final ana = HouseholdState(repo, await currentUser(repo));
    await settle();
    await ana.requestWipe(WipeScope.all);
    await settle();
    await ana.cancelWipe();
    await settle();
    expect(ana.household!.wipe, isNull);
    expect(ana.expenses, isNotEmpty);
    expect(ana.recurring, isNotEmpty);
    ana.dispose();
  });

  test('sin pareja, el borrado es inmediato', () async {
    final repo = MemoryRepository();
    await repo.register('Sol', 'sol@example.com', 'secreto');
    await repo.createHousehold('Mi casa');
    final u = await currentUser(repo);
    final hid = u.householdId!;
    await repo.saveBudget(
        hid, const Budget(id: 'b', category: 'Otros', limit: 100, currency: Currency.ars));
    final s = HouseholdState(repo, u);
    await settle();
    await s.requestWipe(WipeScope.all);
    await settle();
    expect(s.budgets, isEmpty);
    expect(s.household!.wipe, isNull);
    s.dispose();
  });
}
