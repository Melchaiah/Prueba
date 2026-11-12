import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/money.dart';
import '../models/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'dialogs.dart';
import 'household_setup_screen.dart';
import 'summary_tab.dart' show WipeBanner;

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final scope = RepoScope.of(context);
    final h = s.household;
    if (h == null) return const Center(child: CircularProgressIndicator());
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final user = scope.user ?? s.user;
    final prefs = user.prefs;
    final me = h.member(s.me);
    final partner = s.partner;
    final others = user.households.entries.where((e) => e.key != h.id).toList();

    void savePrefs(UserPrefs p) => guard(context, s.repo.savePrefs(p));

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        if (scope.demo)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SectionCard(color: scheme.tertiaryContainer, children: [
              Text(
                'Modo demo: los datos son de ejemplo y se pierden al cerrar. '
                'Con el botón de arriba podés ver la app como tu pareja.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ]),
          ),
        if (h.wipe != null)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: WipeBanner(s)),

        // ---------------------------------------------------------- Hogar
        const SectionHeader('Hogar'),
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: Text(h.name),
          subtitle:
              Text(h.members.map((m) => m.id == s.me ? '${m.name} (vos)' : m.name).join(' y ')),
        ),
        if (partner == null && h.inviteCode != null)
          ListTile(
            leading: const Icon(Icons.group_add_outlined),
            title: const Text('Código para invitar a tu pareja'),
            subtitle: Text(h.inviteCode!, style: t.headlineSmall?.copyWith(letterSpacing: 4)),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: 'Copiar código',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: h.inviteCode!));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Código copiado')));
              },
            ),
          ),
        for (final e in others)
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: Text(e.value.isEmpty ? 'Otro hogar' : e.value),
            subtitle: const Text('Tocá para cambiar a este hogar'),
            onTap: () => guard(context, s.repo.switchHousehold(e.key)),
          ),
        ListTile(
          leading: const Icon(Icons.add_home_outlined),
          title: const Text('Crear o unirme a otro hogar'),
          subtitle: const Text('Para llevar por separado los gastos de otra casa o grupo'),
          onTap: () {
            if (user.households.length >= s.entitlements.maxHouseholds) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      'Llegaste al máximo de ${s.entitlements.maxHouseholds} hogares.')));
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HouseholdSetupScreen(user: user, pushed: true),
            ));
          },
        ),

        // ----------------------------------------------------- Apariencia
        const SectionHeader('Apariencia'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: SegmentedButton<ThemePref>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemePref.system, label: Text('Sistema')),
              ButtonSegment(value: ThemePref.light, label: Text('Claro')),
              ButtonSegment(value: ThemePref.dark, label: Text('Oscuro')),
            ],
            selected: {prefs.theme},
            onSelectionChanged: (v) => savePrefs(prefs.copyWith(theme: v.first)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Text(
            prefs.theme == ThemePref.system
                ? 'Usa el modo claro u oscuro que tenga configurado el celular.'
                : 'Se mantiene fijo aunque cambie la configuración del celular.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            children: [
              for (var i = 0; i < palettes.length; i++)
                Tooltip(
                  message: 'Color ${palettes[i].$1}',
                  child: Semantics(
                    button: true,
                    selected: prefs.palette == i,
                    label: 'Color ${palettes[i].$1}',
                    child: InkResponse(
                      radius: 28,
                      onTap: () => savePrefs(prefs.copyWith(palette: i)),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: palettes[i].$2,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: prefs.palette == i ? scheme.onSurface : Colors.transparent,
                              width: 3,
                            ),
                          ),
                          child: prefs.palette == i
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // ------------------------------------------------ Moneda y formato
        const SectionHeader('Moneda y formato'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: DropdownButtonFormField<Currency>(
            key: ValueKey(s.mainCurrency),
            initialValue: s.mainCurrency,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Moneda principal del hogar'),
            items: [
              for (final c in Currency.values)
                DropdownMenuItem(value: c, child: Text('${c.label} (${c.symbol})')),
            ],
            onChanged: (c) {
              if (c == null || c == s.mainCurrency) return;
              guard(context,
                  s.repo.setCurrencies(s.hid, [c, ...s.currencies.where((x) => x != c)]));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text('Otras monedas que usan', style: t.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            children: [
              for (final c in Currency.values)
                if (c != s.mainCurrency)
                  FilterChip(
                    label: Text(c.code),
                    tooltip: c.label,
                    selected: s.currencies.contains(c),
                    onSelected: (on) => guard(
                      context,
                      s.repo.setCurrencies(s.hid, [
                        for (final x in s.currencies)
                          if (x != c) x,
                        if (on) c,
                      ]),
                    ),
                  ),
            ],
          ),
        ),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text('Mostrar centavos'),
          subtitle: Text('Ejemplo: ${formatMoney(20000050, s.mainCurrency)}'),
          value: prefs.showDecimals,
          onChanged: (v) => savePrefs(prefs.copyWith(showDecimals: v)),
        ),

        // ------------------------------------------------------ Categorías
        SectionHeader(
          'Categorías propias',
          action: TextButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Agregar'),
            onPressed: () => showCategoryDialog(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: h.customCategories.isEmpty
              ? Text(
                  'Además de las que trae la app (Supermercado, Servicios…), pueden sumar las suyas.',
                  style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
              : Wrap(
                  spacing: 8,
                  children: [
                    for (final c in h.customCategories)
                      InputChip(
                        label: Text(c),
                        deleteButtonTooltipMessage: 'Quitar $c',
                        onDeleted: () => guard(
                          context,
                          s.repo.setCategories(s.hid, [
                            for (final x in h.customCategories)
                              if (x != c) x,
                          ]),
                        ),
                      ),
                  ],
                ),
        ),
        if (h.customCategories.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text('Si quitan una, los gastos ya cargados la conservan.',
                style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),

        // ------------------------------------------------------- Cotización
        if (s.fxEnabled) ...[
          const SectionHeader('Cotización del dólar'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: DropdownButtonFormField<FxSource>(
              key: ValueKey(s.fx.source),
              initialValue: s.fx.source,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: 'Qué dólar usar', helperText: s.fx.source.description),
              items: [
                for (final x in FxSource.values)
                  DropdownMenuItem(value: x, child: Text(x.label)),
              ],
              onChanged: (x) {
                if (x == null || x == s.fx.source) return;
                guard(context, s.repo.setFx(s.hid, FxSettings(source: x, manual: s.fx.manual)));
              },
            ),
          ),
          if (s.fx.source == FxSource.manual)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: const Text('Valor del dólar'),
              subtitle: Text(s.fx.manual > 0
                  ? formatMoney(s.fx.manual, Currency.ars)
                  : 'Tocá para cargarlo'),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editManualRate(context, s),
            )
          else
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              title: Text(s.usdQuote != null
                  ? formatMoney(s.usdQuote!.rate, Currency.ars)
                  : s.fxLoading
                      ? 'Consultando…'
                      : 'No se pudo consultar'),
              subtitle: Text(s.usdQuote?.date != null
                  ? 'Actualizado el ${formatDate(s.usdQuote!.date!)} · se consulta al abrir la app'
                  : 'Revisá la conexión y tocá actualizar'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar cotización',
                onPressed: s.fxLoading ? null : s.refreshFx,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(
              'Se usa para mostrar cuánto son en pesos los gastos en dólares. '
              'La elección vale para los dos.',
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],

        // ------------------------------------------------------ Privacidad
        const SectionHeader('Privacidad de tus gastos personales'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            'Los gastos compartidos siempre los ven los dos. '
            'Elegí qué puede ver ${partner?.name ?? 'tu pareja'} de tus gastos personales:',
            style: t.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        RadioGroup<PrivacyMode>(
          groupValue: me?.privacy ?? PrivacyMode.allVisible,
          onChanged: (v) => guard(context, s.repo.setPrivacy(s.hid, v!)),
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

        // ------------------------------------------------------------ Plan
        const SectionHeader('Plan'),
        ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text('Plan ${s.entitlements.planLabel}'),
          subtitle: const Text('Incluye todas las funciones de la app.'),
        ),

        // ----------------------------------------------------------- Datos
        const SectionHeader('Datos del hogar'),
        ListTile(
          leading: Icon(Icons.delete_sweep_outlined, color: scheme.error),
          title: const Text('Borrar datos y empezar de cero'),
          subtitle: Text(partner == null
              ? 'Útil si estuviste probando la app.'
              : 'Útil si estuvieron probando la app. ${partner.name} lo tiene que aceptar.'),
          enabled: h.wipe == null,
          onTap: () => _confirmWipe(context, s),
        ),

        // ---------------------------------------------------------- Cuenta
        const SectionHeader('Cuenta'),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Cerrar sesión'),
          subtitle: Text(user.name),
          onTap: s.repo.signOut,
        ),
      ],
    );
  }
}

Future<void> _editManualRate(BuildContext context, HouseholdState s) {
  final form = GlobalKey<FormState>();
  final amount =
      TextEditingController(text: s.fx.manual > 0 ? moneyToInput(s.fx.manual) : '');
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Valor del dólar'),
      content: Form(
        key: form,
        child: AmountField(
            controller: amount,
            currency: Currency.ars,
            label: 'Pesos por cada dólar',
            autofocus: true),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop(ctx);
            guard(
                context,
                s.repo.setFx(s.hid,
                    FxSettings(source: FxSource.manual, manual: parseMoney(amount.text)!)));
          },
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

Future<void> _confirmWipe(BuildContext context, HouseholdState s) async {
  var scope = WipeScope.movements;
  final partner = s.partner;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        icon: Icon(Icons.delete_sweep_outlined, color: Theme.of(ctx).colorScheme.error),
        title: const Text('Borrar datos del hogar'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            RadioGroup<WipeScope>(
              groupValue: scope,
              onChanged: (v) => setState(() => scope = v!),
              child: const Column(children: [
                RadioListTile<WipeScope>(
                  contentPadding: EdgeInsets.zero,
                  value: WipeScope.movements,
                  title: Text('Solo movimientos'),
                  subtitle: Text(
                      'Gastos, cuotas, ingresos y pagos. Quedan los gastos fijos y los presupuestos.'),
                ),
                RadioListTile<WipeScope>(
                  contentPadding: EdgeInsets.zero,
                  value: WipeScope.all,
                  title: Text('Todo'),
                  subtitle: Text('También los gastos fijos, los presupuestos y las metas de ahorro.'),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Text(
              partner == null
                  ? 'Se borra ahora y no se puede deshacer.'
                  : 'No se borra nada hasta que ${partner.name} lo acepte desde su celular. '
                      'Después no se puede deshacer.',
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(partner == null ? 'Borrar' : 'Pedir borrado'),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return;
  try {
    await s.requestWipe(scope);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No se pudo enviar el pedido. Revisá la conexión y probá de nuevo.')));
    }
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(partner == null
            ? 'Datos borrados.'
            : 'Pedido enviado. Falta que ${partner.name} lo acepte.')));
  }
}
