// ARCHIVO DE RELLENO. Reemplazalo ejecutando `flutterfire configure`
// (ver README). Mientras Firebase no esté configurado, la app arranca en
// modo demo con datos de ejemplo guardados solo en memoria.

import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform =>
      throw UnsupportedError('Firebase todavía no está configurado.');
}
