import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/logic/money.dart';
import 'package:gastos_pareja/models/models.dart';

void main() {
  test('parseMoney acepta formatos comunes', () {
    expect(parseMoney('1234'), 123400);
    expect(parseMoney('1234,5'), 123450);
    expect(parseMoney('1.234,56'), 123456);
    expect(parseMoney('1234.56'), 123456);
    expect(parseMoney('1.234'), 123400);
    expect(parseMoney('1.234.567'), 123456700);
    expect(parseMoney(r'$ 2.500'), 250000);
    expect(parseMoney(''), isNull);
    expect(parseMoney('abc'), isNull);
    expect(parseMoney('1,234,5'), isNull);
  });

  test('formatMoney', () {
    expect(formatMoney(123456, Currency.ars), r'$ 1.234,56');
    expect(formatMoney(150000, Currency.usd, compact: true), r'US$ 1.500');
    expect(formatMoney(-5000, Currency.ars), r'-$ 50,00');
  });

  test('moneyToInput', () {
    expect(moneyToInput(123450), '1234,50');
    expect(moneyToInput(120000), '1200');
    expect(parseMoney(moneyToInput(98765)), 98765);
  });
}
