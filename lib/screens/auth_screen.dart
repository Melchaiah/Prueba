import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = RepoScope.of(context).repo;
    try {
      if (_register) {
        await repo.register(_name.text.trim(), _email.text, _password.text);
      } else {
        await repo.signIn(_email.text, _password.text);
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = _authMessage(e.code));
    } catch (e) {
      setState(() => _error = 'No se pudo continuar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _authMessage(String code) => switch (code) {
        'invalid-email' => 'El email no es válido.',
        'invalid-credential' || 'wrong-password' || 'user-not-found' =>
          'Email o contraseña incorrectos.',
        'email-already-in-use' => 'Ya existe una cuenta con ese email.',
        'weak-password' => 'La contraseña debe tener al menos 6 caracteres.',
        'network-request-failed' => 'Sin conexión a internet.',
        _ => 'Error: $code',
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: CircleAvatar(
                      radius: 44,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(Icons.savings_outlined,
                          size: 44, color: Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Gastos en Pareja', style: t.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text('Las finanzas de los dos, en un solo lugar',
                      style: t.bodyMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  if (_register) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Tu nombre'),
                      textCapitalization: TextCapitalization.words,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingresá tu nombre' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => (v == null || !v.contains('@')) ? 'Ingresá un email válido' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration(labelText: 'Contraseña'),
                    obscureText: true,
                    validator: (v) => (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_register ? 'Crear cuenta' : 'Ingresar'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _register = !_register),
                    child: Text(_register ? 'Ya tengo cuenta' : 'Crear una cuenta nueva'),
                  ),
                ],
              ),
            )),
          ),
        ),
      ),
    );
  }
}
