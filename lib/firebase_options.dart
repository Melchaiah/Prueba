// Configuración de Firebase del proyecto "Gastos pareja"
// (gastos-pareja-dca73). Estos valores no son secretos: viajan dentro de la
// app. Lo que protege los datos son las reglas de firestore.rules.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return android;
    }
    // iOS y web todavía no están registrados en Firebase: la app arranca en
    // modo demo en esas plataformas.
    throw UnsupportedError('Firebase no está configurado para esta plataforma.');
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAy3Ahsiu4L6D_r2K5cBcwx8n2kcMd9UDw',
    appId: '1:529446305280:android:2d54e2c630e2164639a2e5',
    messagingSenderId: '529446305280',
    projectId: 'gastos-pareja-dca73',
  );
}
