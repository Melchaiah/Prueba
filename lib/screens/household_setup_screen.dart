import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../data/repository.dart';

/// Primer paso después de registrarse: crear el hogar o unirse al de la pareja.
class HouseholdSetupScreen extends StatefulWidget {
  const HouseholdSetupScreen({super.key, required this.user});
  final AppUser user;

  @override
  State<HouseholdSetupScreen> createState() => _HouseholdSetupScreenState();
}

class _HouseholdSetupScreenState extends State<HouseholdSetupScreen> {
  final _name = TextEditingController(text: 'Nuestra casa');
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } catch (e) {
      setState(() => _error = e is StateError ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = RepoScope.of(context).repo;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hola, ${widget.user.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Salir', onPressed: repo.signOut),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Crear un hogar nuevo', style: t.titleLarge),
          const SizedBox(height: 4),
          const Text('Después vas a recibir un código para invitar a tu pareja.'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nombre del hogar', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.home),
            label: const Text('Crear hogar'),
            onPressed: _busy ? null : () => _run(() => repo.createHousehold(_name.text.trim())),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Row(children: [
              Expanded(child: Divider()),
              Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('o')),
              Expanded(child: Divider()),
            ]),
          ),
          Text('Unirme al hogar de mi pareja', style: t.titleLarge),
          const SizedBox(height: 4),
          const Text('Pedile el código de invitación que aparece en Ajustes.'),
          const SizedBox(height: 12),
          TextField(
            controller: _code,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Código de invitación', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.group_add),
            label: const Text('Unirme'),
            onPressed: _busy ? null : () => _run(() => repo.joinHousehold(_code.text)),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
