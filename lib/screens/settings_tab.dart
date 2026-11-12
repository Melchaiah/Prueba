import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models/models.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final scope = RepoScope.of(context);
    final h = s.household;
    final t = Theme.of(context).textTheme;
    if (h == null) return const Center(child: CircularProgressIndicator());
    final me = h.member(s.me);
    final partner = s.partner;

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (scope.demo)
          Card(
            margin: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Modo demo: los datos son de ejemplo y se guardan solo en memoria. '
                'Para usar la app de verdad hay que configurar Firebase (ver README). '
                'Con el botón de arriba podés ver la app como tu pareja.',
              ),
            ),
          ),
        ListTile(
          leading: const Icon(Icons.home),
          title: Text(h.name),
          subtitle: Text(h.members.map((m) => m.id == s.me ? '${m.name} (vos)' : m.name).join(' y ')),
        ),
        if (partner == null && h.inviteCode != null)
          ListTile(
            leading: const Icon(Icons.group_add),
            title: const Text('Código para invitar a tu pareja'),
            subtitle: Text(h.inviteCode!, style: t.headlineSmall?.copyWith(letterSpacing: 4)),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: h.inviteCode!));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Código copiado')));
              },
            ),
          ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Privacidad de tus gastos personales', style: t.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Los gastos compartidos siempre los ven los dos. '
            'Elegí qué puede ver ${partner?.name ?? 'tu pareja'} de tus gastos personales:',
            style: t.bodyMedium,
          ),
        ),
        RadioGroup<PrivacyMode>(
          groupValue: me?.privacy ?? PrivacyMode.allVisible,
          onChanged: (v) => s.repo.setPrivacy(s.hid, v!),
          child: Column(children: [
            for (final mode in PrivacyMode.values)
              RadioListTile<PrivacyMode>(
                value: mode,
                title: Text(mode.title),
                subtitle: Text(mode.description),
              ),
          ]),
        ),
        if (partner != null)
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text('${partner.name} eligió: ${partner.privacy.title}'),
            subtitle: Text(switch (partner.privacy) {
              PrivacyMode.allVisible => 'Ves todos sus gastos personales.',
              PrivacyMode.sharedOnly => 'No ves sus gastos personales.',
              PrivacyMode.perExpense => 'Ves solo los gastos personales que marcó como visibles.',
            }),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          onTap: s.repo.signOut,
        ),
      ],
    );
  }
}
