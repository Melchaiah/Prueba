// Planes y permisos. Hoy todo es gratis; esta capa existe para que, si algún
// día hay un plan pago, cada función consulte acá qué está habilitado en vez
// de repartir condiciones por toda la app.
//
// El plan vive en el documento del hogar (`plan`) y las reglas de Firestore
// no dejan que la app lo cambie: lo tendría que escribir un servidor después
// de validar la compra (por ejemplo una Cloud Function con Google Play
// Billing o RevenueCat).

import '../models/models.dart';

enum Plan { free, premium }

class Entitlements {
  const Entitlements(this.plan);
  final Plan plan;

  factory Entitlements.of(Household? h) =>
      Entitlements(h?.plan == 'premium' ? Plan.premium : Plan.free);

  String get planLabel => plan == Plan.premium ? 'Premium' : 'Gratis';

  // Mientras no haya plan pago, el plan gratis incluye todo.

  /// Cantidad de hogares en los que puede estar una cuenta.
  int get maxHouseholds => 10;

  /// Monedas adicionales a la principal.
  int get maxExtraCurrencies => Currency.values.length - 1;

  bool get budgets => true;
  bool get recurring => true;
  bool get installments => true;
}
