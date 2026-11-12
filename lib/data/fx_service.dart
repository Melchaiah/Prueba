// Cotización del dólar desde fuentes públicas y gratuitas.
//
// - BCRA: tipo de cambio de referencia (api.bcra.gob.ar).
// - dolarapi.com: oficial de bancos, blue, MEP y tarjeta.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

const _timeout = Duration(seconds: 12);

/// Centavos de peso por dólar a partir de un valor en pesos.
int _cents(num pesos) => (pesos * 100).round();

/// Lee la respuesta de `api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones/USD`.
FxQuote parseBcra(String body) {
  final results = (jsonDecode(body) as Map)['results'] as List;
  final last = results.last as Map;
  final detail = (last['detalle'] as List)
      .cast<Map>()
      .firstWhere((d) => d['codigoMoneda'] == 'USD');
  final rate = _cents(detail['tipoCotizacion'] as num);
  if (rate <= 0) throw const FormatException('Cotización vacía');
  return FxQuote(rate, DateTime.tryParse(last['fecha'] as String? ?? ''));
}

/// Lee la respuesta de `dolarapi.com/v1/dolares/{casa}` (precio de venta).
FxQuote parseDolarApi(String body) {
  final m = jsonDecode(body) as Map;
  final rate = _cents(m['venta'] as num);
  if (rate <= 0) throw const FormatException('Cotización vacía');
  return FxQuote(rate, DateTime.tryParse(m['fechaActualizacion'] as String? ?? '')?.toLocal());
}

Future<String> _get(http.Client client, String url) async {
  final r = await client.get(Uri.parse(url)).timeout(_timeout);
  if (r.statusCode != 200) throw http.ClientException('HTTP ${r.statusCode}');
  return utf8.decode(r.bodyBytes);
}

Future<FxQuote> _dolarApi(http.Client client, String casa) async =>
    parseDolarApi(await _get(client, 'https://dolarapi.com/v1/dolares/$casa'));

/// Trae la cotización de [source]. Tira una excepción si no hay conexión.
Future<FxQuote> fetchUsdQuote(FxSource source, {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    switch (source) {
      case FxSource.bcra:
        try {
          return parseBcra(await _get(
              c, 'https://api.bcra.gob.ar/estadisticascambiarias/v1.0/Cotizaciones/USD'));
        } catch (_) {
          // Si el sitio del BCRA no responde, el mayorista es el mismo valor.
          return await _dolarApi(c, 'mayorista');
        }
      case FxSource.oficial:
        return await _dolarApi(c, 'oficial');
      case FxSource.blue:
        return await _dolarApi(c, 'blue');
      case FxSource.mep:
        return await _dolarApi(c, 'bolsa');
      case FxSource.tarjeta:
        return await _dolarApi(c, 'tarjeta');
      case FxSource.manual:
        throw ArgumentError('La cotización manual no se consulta');
    }
  } finally {
    if (client == null) c.close();
  }
}
