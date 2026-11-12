import 'package:intl/intl.dart';

import '../models/models.dart';

final _fmt = NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 2);
final _fmtNoDecimals = NumberFormat.currency(locale: 'es_AR', symbol: '', decimalDigits: 0);

/// Formatea centavos: `$ 1.234,50` / `US$ 12,00`. Omite los decimales si son
/// cero y [compact] es true.
String formatMoney(int cents, Currency c, {bool compact = false}) {
  final neg = cents < 0;
  final abs = cents.abs();
  final f = (compact && abs % 100 == 0) ? _fmtNoDecimals : _fmt;
  return '${neg ? '-' : ''}${c.symbol} ${f.format(abs / 100).trim()}';
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

/// Texto editable para un monto en centavos (`1234,5` -> `1234,50`).
String moneyToInput(int cents) {
  final s = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
  return s.endsWith(',00') ? s.substring(0, s.length - 3) : s;
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
