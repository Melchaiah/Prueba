import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/data/fx_service.dart';
import 'package:gastos_pareja/data/memory_repository.dart';
import 'package:gastos_pareja/logic/finance.dart';
import 'package:gastos_pareja/models/models.dart';

void main() {
  test('cotización: lee la respuesta del BCRA', () {
    final q = parseBcra('{"status":200,"results":[{"fecha":"2026-11-11","detalle":'
        '[{"codigoMoneda":"USD","descripcion":"DOLAR E.E.U.U.","tipoPase":0.0,"tipoCotizacion":1544.00000000}]}]}');
    expect(q.rate, 154400);
    expect(q.date, DateTime(2026, 11, 11));
  });

  test('cotización: lee la respuesta de dolarapi (venta)', () {
    final q = parseDolarApi('{"moneda":"USD","casa":"bolsa","compra":1567.8,"venta":1578.3,'
        '"fechaActualizacion":"2026-11-11T20:56:00.000Z"}');
    expect(q.rate, 157830);
    expect(q.date, isNotNull);
  });

  test('convierte dólares a pesos', () {
    expect(usdToArs(1200, 154400), 1852800); // US$ 12 a $ 1.544 = $ 18.528
  });

  test('metas: ahorrado, por persona y cuota mensual necesaria', () {
    final g = Goal(
      id: 'g',
      name: 'Viaje',
      target: 100000,
      currency: Currency.ars,
      deadline: const YearMonth(2026, 12),
      contributions: [
        Contribution(memberId: 'a', amount: 30000, date: DateTime(2026, 10, 1)),
        Contribution(memberId: 'b', amount: 20000, date: DateTime(2026, 10, 2)),
        Contribution(memberId: 'a', amount: -10000, date: DateTime(2026, 10, 3)),
      ],
    );
    expect(g.saved, 40000);
    expect(g.savedBy('a'), 20000);
    expect(g.ratio, 0.4);
    // Faltan 60.000 en noviembre y diciembre.
    expect(g.monthlyNeeded(const YearMonth(2026, 11)), 30000);
    expect(g.monthlyNeeded(const YearMonth(2027, 1)), isNull);
    final back = Goal.fromMap('g', g.toMap());
    expect(back.saved, 40000);
    expect(back.deadline, const YearMonth(2026, 12));
  });

  test('categorías: las propias van antes de Otros y sin repetir', () {
    const h = Household(id: 'h', name: 'x', members: [], customCategories: ['Mascotas', 'Salud']);
    expect(h.categories.last, 'Otros');
    expect(h.categories.where((c) => c == 'Salud').length, 1);
    expect(h.categories, contains('Mascotas'));
  });

  test('evolución: total compartido por mes, con cuotas y fijos', () {
    const m = YearMonth(2026, 11);
    final totals = sharedTotalsByMonth(
      last: m,
      count: 3,
      currency: Currency.ars,
      expenses: [
        Expense(id: '1', description: '', category: 'Hogar', amount: 3000, currency: Currency.ars, date: DateTime(2026, 10, 1), paidBy: 'a', isShared: true, split: const {'a': 100}, installments: 3, firstInstallment: m.add(-1)),
        Expense(id: '2', description: '', category: 'Ropa', amount: 500, currency: Currency.ars, date: DateTime(2026, 11, 1), paidBy: 'a', isShared: false, split: const {'a': 100}, firstInstallment: m),
        Expense(id: '3', description: '', category: 'Ropa', amount: 700, currency: Currency.usd, date: DateTime(2026, 11, 1), paidBy: 'a', isShared: true, split: const {'a': 100}, firstInstallment: m),
      ],
      recurring: [
        RecurringExpense(id: 'r', description: '', category: 'Servicios', amount: 200, currency: Currency.ars, paidBy: 'a', isShared: true, split: const {'a': 100}, start: m),
      ],
    );
    expect(totals.map((e) => e.$2).toList(), [0, 1000, 1200]);
    expect(totals.first.$1, const YearMonth(2026, 9));
  });

  test('repositorio demo: categorías, cotización y metas', () async {
    final repo = MemoryRepository(withDemoData: true);
    await repo.setCategories('demo', ['Mascotas']);
    await repo.setFx('demo', const FxSettings(source: FxSource.manual, manual: 150000));
    final h = await repo.watchHousehold('demo').first;
    expect(h.customCategories, ['Mascotas']);
    expect(h.fx.source, FxSource.manual);
    final goals = await repo.watchGoals('demo').first;
    expect(goals.single.name, 'Vacaciones');
    await repo.deleteGoal('demo', goals.single.id);
    expect(await repo.watchGoals('demo').first, isEmpty);
  });
}
