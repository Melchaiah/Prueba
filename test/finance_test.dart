import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/logic/finance.dart';
import 'package:gastos_pareja/models/models.dart';

const a = 'ana', b = 'juan';
final ym = const YearMonth(2026, 11);

Expense exp({
  int amount = 10000,
  String paidBy = a,
  bool shared = true,
  Shares split = const {a: 50, b: 50},
  int installments = 1,
  YearMonth? first,
  Currency currency = Currency.ars,
  bool visible = true,
}) =>
    Expense(
      id: 'x',
      description: 'x',
      category: 'Otros',
      amount: amount,
      currency: currency,
      date: DateTime(2026, 11, 1),
      paidBy: paidBy,
      isShared: shared,
      split: split,
      installments: installments,
      firstInstallment: first ?? ym,
      visibleToPartner: visible,
    );

void main() {
  group('YearMonth', () {
    test('suma meses cruzando el año', () {
      expect(ym.add(2), const YearMonth(2027, 1));
      expect(const YearMonth(2027, 1).add(-1), const YearMonth(2026, 12));
      expect(const YearMonth(2027, 2).monthsSince(ym), 3);
    });
    test('key ida y vuelta', () {
      expect(YearMonth.parse(ym.key), ym);
      expect(const YearMonth(2026, 3).key, '2026-03');
    });
  });

  group('cuotas', () {
    test('el resto de la división va a la primera cuota', () {
      expect(installmentAmount(1000, 3, 1), 334);
      expect(installmentAmount(1000, 3, 2), 333);
      expect(installmentAmount(1000, 3, 3), 333);
    });

    test('cada cuota cae en su mes', () {
      final e = exp(amount: 60000, installments: 6);
      expect(chargesForMonth(ym.add(-1), [e], []), isEmpty);
      expect(chargesForMonth(ym, [e], []).single.installment, 1);
      final last = chargesForMonth(ym.add(5), [e], []).single;
      expect(last.installment, 6);
      expect(last.amount, 10000);
      expect(chargesForMonth(ym.add(6), [e], []), isEmpty);
    });

    test('chargesUpTo no incluye cuotas futuras', () {
      final e = exp(amount: 60000, installments: 6);
      expect(chargesUpTo(ym.add(2), [e], []).length, 3);
    });
  });

  group('gastos recurrentes', () {
    final r = RecurringExpense(
      id: 'r',
      description: 'Alquiler',
      category: 'Alquiler / Expensas',
      amount: 50000,
      currency: Currency.ars,
      paidBy: a,
      isShared: true,
      split: const {a: 50, b: 50},
      start: ym,
      end: ym.add(2),
    );

    test('aparece solo entre inicio y fin', () {
      expect(chargesForMonth(ym.add(-1), [], [r]), isEmpty);
      expect(chargesForMonth(ym, [], [r]).single.recurring, isTrue);
      expect(chargesForMonth(ym.add(2), [], [r]), hasLength(1));
      expect(chargesForMonth(ym.add(3), [], [r]), isEmpty);
    });

    test('monto ajustado en un mes puntual', () {
      final adj = r.withOverride(ym.add(1), 80000);
      expect(chargesForMonth(ym, [], [adj]).single.amount, 50000);
      final c = chargesForMonth(ym.add(1), [], [adj]).single;
      expect((c.amount, c.adjusted), (80000, true));
      expect(chargesForMonth(ym.add(2), [], [adj]).single.adjusted, isFalse);
      // El saldo acumulado usa el monto de cada mes.
      expect(chargesUpTo(ym.add(2), [], [adj]).fold<int>(0, (a, c) => a + c.amount), 180000);
      // Volver al habitual (o poner el mismo monto) quita el ajuste.
      expect(adj.withOverride(ym.add(1), null).overrides, isEmpty);
      expect(adj.withOverride(ym.add(1), 50000).overrides, isEmpty);
    });

    test('mes marcado sin pago no genera cargo', () {
      final skip = r.withOverride(ym.add(1), 0);
      expect(chargesForMonth(ym.add(1), [], [skip]), isEmpty);
      expect(chargesUpTo(ym.add(2), [], [skip]).length, 2);
    });

    test('los ajustes sobreviven a guardar y leer', () {
      final adj = r.withOverride(ym.add(1), 80000).withOverride(ym, 0);
      final back = RecurringExpense.fromMap('r', adj.toMap());
      expect(back.overrides, {ym.add(1): 80000, ym: 0});
      expect(RecurringExpense.fromMap('r', r.toMap()..remove('overrides')).overrides, isEmpty);
    });

    test('chargesUpTo genera un cargo por mes', () {
      expect(chargesUpTo(ym.add(10), [], [r]).length, 3);
      expect(chargesUpTo(ym.add(1), [], [r]).length, 2);
    });
  });

  group('reparto', () {
    test('shareAmounts suma exacto', () {
      final s = shareAmounts(1001, {a: 50, b: 50});
      expect(s[a]! + s[b]!, 1001);
      final p = shareAmounts(10000, {a: 33.33, b: 66.67});
      expect(p[a]! + p[b]!, 10000);
    });

    test('proporcional a ingresos del mes', () {
      final incomes = [
        Income(id: '1', memberId: a, description: '', amount: 180000, currency: Currency.ars, month: ym),
        Income(id: '2', memberId: b, description: '', amount: 120000, currency: Currency.ars, month: ym),
        // Otro mes y otra moneda no cuentan.
        Income(id: '3', memberId: b, description: '', amount: 999999, currency: Currency.ars, month: ym.add(-1)),
        Income(id: '4', memberId: b, description: '', amount: 999999, currency: Currency.usd, month: ym),
      ];
      expect(proportionalSplit([a, b], incomes, ym), {a: 60.0, b: 40.0});
    });

    test('sin ingresos reparte en partes iguales', () {
      expect(proportionalSplit([a, b], [], ym), {a: 50.0, b: 50.0});
    });
  });

  group('saldos', () {
    test('quien pagó queda a favor por la parte del otro', () {
      final bal = computeBalances(
        memberIds: [a, b],
        charges: chargesUpTo(ym, [exp(amount: 10000, split: {a: 60, b: 40})], []),
        settlements: [],
      )[Currency.ars]!;
      expect(bal, {a: 4000, b: -4000});
      final d = debtFor(bal)!;
      expect((d.from, d.to, d.amount), (b, a, 4000));
    });

    test('los gastos personales no afectan el saldo', () {
      final bal = computeBalances(
        memberIds: [a, b],
        charges: chargesUpTo(ym, [exp(shared: false, split: {a: 100})], []),
        settlements: [],
      )[Currency.ars];
      expect(bal, isNull);
    });

    test('un pago salda la deuda', () {
      final bal = computeBalances(
        memberIds: [a, b],
        charges: chargesUpTo(ym, [exp(amount: 10000)], []),
        settlements: [
          Settlement(id: 's', from: b, to: a, amount: 5000, currency: Currency.ars, date: DateTime(2026, 11, 2)),
        ],
      )[Currency.ars]!;
      expect(debtFor(bal), isNull);
    });

    test('cada moneda tiene su propio saldo', () {
      final bal = computeBalances(
        memberIds: [a, b],
        charges: chargesUpTo(ym, [
          exp(amount: 10000),
          exp(amount: 2000, paidBy: b, currency: Currency.usd),
        ], []),
        settlements: [],
      );
      expect(bal[Currency.ars], {a: 5000, b: -5000});
      expect(bal[Currency.usd], {a: -1000, b: 1000});
    });

    test('cuotas: solo cuenta lo vencido', () {
      final bal = computeBalances(
        memberIds: [a, b],
        charges: chargesUpTo(ym.add(1), [exp(amount: 60000, installments: 6)], []),
        settlements: [],
      )[Currency.ars]!;
      expect(bal[b], -10000); // 2 cuotas de 10000, la mitad cada una
    });
  });

  group('resumen y presupuestos', () {
    test('summarizeMonth separa compartido y personal', () {
      final charges = chargesForMonth(ym, [
        exp(amount: 10000, split: {a: 60, b: 40}),
        exp(amount: 3000, shared: false, paidBy: b, split: {b: 100}),
      ], []);
      final s = summarizeMonth(month: ym, charges: charges, incomes: []);
      expect(s.sharedTotal[Currency.ars], 10000);
      expect(s.paidShared[Currency.ars], {a: 10000});
      expect(s.shareOfShared[Currency.ars], {a: 6000, b: 4000});
      expect(s.personal[Currency.ars], {b: 3000});
    });

    test('niveles de presupuesto', () {
      const budget = Budget(id: 'b', category: 'Otros', limit: 10000, currency: Currency.ars);
      BudgetLevel level(int spent) {
        final s = summarizeMonth(
            month: ym, charges: chargesForMonth(ym, [exp(amount: spent)], []), incomes: []);
        return budgetStatuses([budget], s).single.level;
      }

      expect(level(5000), BudgetLevel.ok);
      expect(level(8000), BudgetLevel.warning);
      expect(level(12000), BudgetLevel.exceeded);
    });
  });

  group('privacidad', () {
    Household house(PrivacyMode bPrivacy) => Household(id: 'h', name: 'h', members: [
          const Member(id: a, name: 'Ana'),
          Member(id: b, name: 'Juan', privacy: bPrivacy),
        ]);
    final personalB = exp(shared: false, paidBy: b, split: {b: 100}, visible: false);
    final personalBVisible = exp(shared: false, paidBy: b, split: {b: 100}, visible: true);

    test('compartidos siempre visibles', () {
      expect(isVisibleTo(exp(paidBy: b), a, house(PrivacyMode.sharedOnly)), isTrue);
    });
    test('todo visible', () {
      expect(isVisibleTo(personalB, a, house(PrivacyMode.allVisible)), isTrue);
    });
    test('solo compartidos', () {
      expect(isVisibleTo(personalBVisible, a, house(PrivacyMode.sharedOnly)), isFalse);
    });
    test('elegir por gasto', () {
      expect(isVisibleTo(personalB, a, house(PrivacyMode.perExpense)), isFalse);
      expect(isVisibleTo(personalBVisible, a, house(PrivacyMode.perExpense)), isTrue);
    });
    test('el dueño siempre ve lo suyo', () {
      expect(isVisibleTo(personalB, b, house(PrivacyMode.sharedOnly)), isTrue);
    });
  });
}
