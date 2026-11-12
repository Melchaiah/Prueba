import 'package:flutter/services.dart';
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

  test('moneyToInput usa puntos de miles', () {
    expect(moneyToInput(123450), '1.234,50');
    expect(moneyToInput(20000000), '200.000');
    expect(parseMoney(moneyToInput(98765)), 98765);
  });

  group('MoneyInputFormatter', () {
    // Simula tipear [typed] carácter por carácter al final del texto.
    String type(String typed, {bool decimals = true}) {
      final f = MoneyInputFormatter(decimals: decimals);
      var v = TextEditingValue.empty;
      for (final ch in typed.split('')) {
        final text = v.text + ch;
        v = f.formatEditUpdate(
            v, TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
      }
      return v.text;
    }

    test('agrega puntos de miles mientras se escribe', () {
      expect(type('200000'), '200.000');
      expect(type('1234567'), '1.234.567');
      expect(type('999'), '999');
    });

    test('coma o punto tipeado es el separador decimal', () {
      expect(type('1234,5'), '1.234,5');
      expect(type('1234.56'), '1.234,56');
      expect(type('1234,567'), '1.234,56');
      expect(type(',5'), '0,5');
    });

    test('sin decimales ignora la coma', () {
      expect(type('1234,56', decimals: false), '123.456');
    });

    test('quita ceros a la izquierda', () {
      expect(type('007'), '7');
      expect(type('0'), '0');
    });

    test('mantiene el cursor al editar en el medio', () {
      final f = MoneyInputFormatter(decimals: true);
      // "1.234" -> inserta un 9 después del 1: "19.234" con el cursor tras el 9.
      final v = f.formatEditUpdate(
        const TextEditingValue(text: '1.234', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(text: '19.234', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(v.text, '19.234');
      expect(v.selection.baseOffset, 2);
      // Borra el 1 de "1.234": queda "234".
      final d = f.formatEditUpdate(
        const TextEditingValue(text: '1.234', selection: TextSelection.collapsed(offset: 1)),
        const TextEditingValue(text: '.234', selection: TextSelection.collapsed(offset: 0)),
      );
      expect(d.text, '234');
      expect(d.selection.baseOffset, 0);
    });

    test('lo formateado se puede leer de vuelta', () {
      expect(parseMoney(type('200000')), 20000000);
      expect(parseMoney(type('1234,5')), 123450);
    });
  });

  test('sin centavos: formato e ingreso redondeados', () {
    moneyShowDecimals = false;
    addTearDown(() => moneyShowDecimals = true);
    expect(formatMoney(123456, Currency.ars), r'$ 1.235');
    expect(moneyToInput(123456), '1.235');
    expect(formatMoney(20000000, Currency.eur), '€ 200.000');
  });
}
