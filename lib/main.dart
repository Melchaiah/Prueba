import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'data/firestore_repository.dart';
import 'data/memory_repository.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'logic/money.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/household_setup_screen.dart';
import 'theme.dart';

/// `flutter run --dart-define=DEMO=true` fuerza el modo demo.
const forceDemo = bool.fromEnvironment('DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var demo = forceDemo;
  if (!demo) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Firebase no disponible ($e). Arrancando en modo demo.');
      demo = true;
    }
  }
  final Repository repo = demo ? MemoryRepository(withDemoData: true) : FirestoreRepository();
  runApp(GastosApp(repo: repo, demo: demo));
}

class GastosApp extends StatefulWidget {
  const GastosApp({super.key, required this.repo, this.demo = false});
  final Repository repo;
  final bool demo;

  @override
  State<GastosApp> createState() => _GastosAppState();
}

class _GastosAppState extends State<GastosApp> {
  late final Stream<AppUser?> _userStream = widget.repo.watchUser();
  HouseholdState? _state;

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  HouseholdState _stateFor(AppUser user) {
    final s = _state;
    if (s != null && s.user.id == user.id && s.user.householdId == user.householdId) {
      return s..updateUser(user);
    }
    s?.dispose();
    return _state = HouseholdState(widget.repo, user);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppUser?>(
      stream: _userStream,
      builder: (context, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;
        final user = snap.data;
        final prefs = user?.prefs ?? const UserPrefs();
        moneyShowDecimals = prefs.showDecimals;

        final Widget home;
        if (waiting) {
          home = const Scaffold(body: Center(child: CircularProgressIndicator()));
        } else if (user == null) {
          home = const AuthScreen();
        } else if (user.householdId == null) {
          home = HouseholdSetupScreen(user: user);
        } else {
          home = HouseholdScope(
            state: _stateFor(user),
            child: HomeScreen(key: ValueKey('${user.id}/${user.householdId}')),
          );
        }

        return RepoScope(
          repo: widget.repo,
          demo: widget.demo,
          user: user,
          child: MaterialApp(
            title: 'Gastos en Pareja',
            debugShowCheckedModeBanner: false,
            locale: const Locale('es', 'AR'),
            supportedLocales: const [Locale('es', 'AR'), Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: buildTheme(prefs.palette, Brightness.light),
            darkTheme: buildTheme(prefs.palette, Brightness.dark),
            themeMode: themeModeOf(prefs.theme.name),
            home: home,
          ),
        );
      },
    );
  }
}
