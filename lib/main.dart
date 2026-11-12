import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'data/firestore_repository.dart';
import 'data/memory_repository.dart';
import 'data/repository.dart';
import 'firebase_options.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/household_setup_screen.dart';

/// `flutter run --dart-define=DEMO=true` fuerza el modo demo.
const forceDemo = bool.fromEnvironment('DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Repository repo;
  var demo = forceDemo;
  if (!demo) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Firebase no disponible ($e). Arrancando en modo demo.');
      demo = true;
    }
  }
  repo = demo ? MemoryRepository(withDemoData: true) : FirestoreRepository();
  runApp(GastosApp(repo: repo, demo: demo));
}

class GastosApp extends StatelessWidget {
  const GastosApp({super.key, required this.repo, this.demo = false});
  final Repository repo;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    return RepoScope(
      repo: repo,
      demo: demo,
      child: MaterialApp(
        title: 'Gastos en Pareja',
        debugShowCheckedModeBanner: false,
        locale: const Locale('es', 'AR'),
        supportedLocales: const [Locale('es', 'AR'), Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E7D6B),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF2E7D6B),
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const _Root(),
      ),
    );
  }
}

/// Decide qué pantalla mostrar: login, crear/unirse a un hogar, o la app.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  HouseholdState? _state;
  Stream<AppUser?>? _user;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _user ??= RepoScope.of(context).repo.watchUser();
  }

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  HouseholdState _stateFor(Repository repo, AppUser user) {
    final s = _state;
    if (s != null && s.user.id == user.id && s.user.householdId == user.householdId) {
      return s;
    }
    s?.dispose();
    return _state = HouseholdState(repo, user);
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context).repo;
    return StreamBuilder<AppUser?>(
      stream: _user,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final user = snap.data;
        if (user == null) return const AuthScreen();
        if (user.householdId == null) return HouseholdSetupScreen(user: user);
        final state = _stateFor(repo, user);
        return HouseholdScope(
          state: state,
          child: HomeScreen(key: ValueKey(user.id)),
        );
      },
    );
  }
}
