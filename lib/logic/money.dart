import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/models.dart';

final _fmt = NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 2);
final _fmtNoDecimals = NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0);

final _fmtInt = NumberFormat.decimalPattern('es_AR');

/// Preferencia del usuario: mostrar y cargar centavos. La actualiza la app
/// cuando cambian los ajustes.
bool moneyShowDecimals = true;

/// Formatea centavos: `$ 1.234,50` / `US$ 12,00`. Omite los decimales si son
/// cero y [compact] es true, o si el usuario los desactivó.
String formatMoney(int cents, Currency c, {bool compact = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final String number;
  if (!moneyShowDecimals) {
    number = _fmtNoDecimals.format((abs / 100).round());
  } else {
    number = ((compact && abs % 100 == 0) ? _fmtNoDecimals : _fmt).format(abs / 100);
  }
  return '${neg ? '-' : ''}${c.symbol} ${number.trim()}';
}

/// Convierte texto a centavos. Acepta `1234`, `1234,5`, `1.234,56`,
/// `1234.56` y `1.234`. Devuelve null si no es un número válido.
///
/// Reglas: si hay coma, la coma es el separador decimal y los puntos son
/// de miles. Si no hay coma, un punto seguido de 1 o 2 dígitos al final es
/// decimal; cualquier otro punto es de miles.
int? parseMoney(String input) {
  var s = input.trim().replaceAll(RegExp(r'[\s$]|US'), '');
  if (s.isEmpty) return null;
  if (s.contains(',')) {
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'\.\d{1,2}$').hasMatch(s)) {
    final i = s.lastIndexOf('.');
    s = s.substring(0, i).replaceAll('.', '') + s.substring(i);
  } else {
    s = s.replaceAll('.', '');
  }
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(s)) return null;
  return (double.parse(s) * 100).round();
}

/// Texto editable para un monto en centavos, con el mismo formato que
/// produce [MoneyInputFormatter] (`123450` -> `1.234,50`).
String moneyToInput(int cents) {
  if (!moneyShowDecimals) return _fmtInt.format((cents / 100).round());
  final s = _fmtInt.format(cents ~/ 100);
  final dec = cents % 100;
  return dec == 0 ? s : '$s,${dec.toString().padLeft(2, '0')}';
}

/// Da formato al monto mientras se escribe: agrega los puntos de miles
/// (`200000` -> `200.000`) y acepta coma (o punto) como separador decimal
/// si los decimales están activados.
class MoneyInputFormatter extends TextInputFormatter {
  MoneyInputFormatter({bool? decimals}) : decimals = decimals ?? moneyShowDecimals;
  final bool decimals;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text;
    var cursor = newValue.selection.end.clamp(0, text.length);

    // Un punto recién tipeado se toma como coma decimal (muchos teclados
    // numéricos solo tienen punto). Los puntos de miles los pone el formato.
    if (text.length == oldValue.text.length + 1 && cursor > 0 && text[cursor - 1] == '.') {
      text = text.replaceRange(cursor - 1, cursor, ',');
    }

    // Caracteres significativos (dígitos y la coma) antes del cursor.
    final sigBefore = _significant(text.substring(0, cursor)).length;
    final sig = _significant(text);

    final comma = sig.indexOf(',');
    var intPart = comma < 0 ? sig : sig.substring(0, comma);
    var decPart = comma < 0 ? null : sig.substring(comma + 1).replaceAll(',', '');
    if (!decimals) decPart = null;
    if (decPart != null && decPart.length > 2) decPart = decPart.substring(0, 2);

    final stripped = intPart.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final removedZeros = intPart.length - stripped.length;
    intPart = stripped;
    if (intPart.isEmpty && decPart != null) intPart = '0';

    final out = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) out.write('.');
      out.write(intPart[i]);
    }
    if (decPart != null) out.write(',$decPart');
    final formatted = out.toString();

    // Reubica el cursor después de la misma cantidad de caracteres
    // significativos.
    var target = (sigBefore - removedZeros).clamp(0, sig.length);
    var pos = 0;
    while (pos < formatted.length && target > 0) {
      if (formatted[pos] != '.') target--;
      pos++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: pos),
    );
  }

  String _significant(String s) {
    final b = StringBuffer();
    var hasComma = false;
    for (final ch in s.split('')) {
      if (RegExp(r'\d').hasMatch(ch)) {
        b.write(ch);
      } else if (ch == ',' && !hasComma && decimals) {
        hasComma = true;
        b.write(ch);
      }
    }
    return b.toString();
  }
}

const _monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

String monthLabel(YearMonth m) => '${_monthNames[m.month - 1]} ${m.year}';

String formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatPercent(double v) =>
    '${v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1)}%';
