import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../logic/money.dart';
import '../models/models.dart';

IconData categoryIcon(String c) => switch (c) {
      'Supermercado' => Icons.shopping_cart_outlined,
      'Alquiler / Expensas' => Icons.home_outlined,
      'Servicios' => Icons.bolt_outlined,
      'Transporte' => Icons.directions_bus_outlined,
      'Salidas' => Icons.restaurant_outlined,
      'Salud' => Icons.local_hospital_outlined,
      'Ropa' => Icons.checkroom_outlined,
      'Hogar' => Icons.chair_outlined,
      'Suscripciones' => Icons.subscriptions_outlined,
      'Educación' => Icons.school_outlined,
      'Regalos' => Icons.card_giftcard_outlined,
      'Otros' => Icons.receipt_long_outlined,
      _ => Icons.label_outline,
    };

String? validateAmount(String? v) =>
    (parseMoney(v ?? '') ?? 0) <= 0 ? 'Ingresá un monto mayor a cero' : null;

/// Tarjeta con título y una acción opcional.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.action, required this.children, this.color});
  final String? title;
  final Widget? action;
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Card(
        color: color,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    Expanded(
                      child: Text(title!, style: Theme.of(context).textTheme.titleMedium),
                    ),
                    ?action,
                  ]),
                ),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

/// Título de una sección de lista.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key, this.action, this.dense = false});
  final String text;
  final Widget? action;

  /// Más compacto, para subtítulos dentro de una lista (por ejemplo, días).
  final bool dense;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, dense ? 16 : 20, 12, dense ? 0 : 4),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: dense ? 0 : 48),
          child: Row(children: [
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            ?action,
          ]),
        ),
      );
}

/// Ejecuta una acción que guarda en el servidor y avisa si falla, en vez de
/// fallar en silencio.
Future<void> guard(BuildContext context, Future<void> action) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await action;
  } catch (_) {
    messenger?.showSnackBar(const SnackBar(
      content: Text('No se pudo guardar el cambio. Revisá la conexión y probá de nuevo.'),
    ));
  }
}

/// Círculo con la inicial de una persona.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar(this.name, {super.key, this.highlight = false, this.radius = 20});
  final String name;
  final bool highlight;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: highlight ? scheme.primary : scheme.secondaryContainer,
      foregroundColor: highlight ? scheme.onPrimary : scheme.onSecondaryContainer,
      child: Text(name.isEmpty ? '?' : name.characters.first.toUpperCase(),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: radius * 0.8)),
    );
  }
}

/// Ícono de categoría sobre un círculo de color suave.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.category, {super.key, this.personal = false});
  final String category;
  final bool personal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 22,
      backgroundColor: personal ? scheme.tertiaryContainer : scheme.primaryContainer,
      foregroundColor: personal ? scheme.onTertiaryContainer : scheme.onPrimaryContainer,
      child: Icon(categoryIcon(category), size: 22),
    );
  }
}

/// Campo de monto: agrega los puntos de miles mientras se escribe.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.currency,
    this.label = 'Monto',
    this.autofocus = false,
    this.large = false,
    this.onChanged,
  });
  final TextEditingController controller;
  final Currency currency;
  final String label;
  final bool autofocus;
  final bool large;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      style: large ? Theme.of(context).textTheme.headlineMedium : null,
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${currency.symbol} ',
        hintText: moneyShowDecimals ? '0,00' : '0',
      ),
      keyboardType: TextInputType.numberWithOptions(decimal: moneyShowDecimals),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
        MoneyInputFormatter(),
      ],
      validator: validateAmount,
      onChanged: onChanged,
    );
  }
}

/// Selector de moneda entre las habilitadas en el hogar. No se muestra si
/// hay una sola.
class CurrencyPicker extends StatelessWidget {
  const CurrencyPicker({super.key, required this.value, required this.onChanged});
  final Currency value;
  final ValueChanged<Currency> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = {...HouseholdScope.of(context).currencies, value}.toList();
    if (options.length < 2) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<Currency>(
        showSelectedIcon: false,
        segments: [for (final c in options) ButtonSegment(value: c, label: Text(c.code))],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class MemberPicker extends StatelessWidget {
  const MemberPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final id in s.memberIds) ButtonSegment(value: id, label: Text(s.nameOf(id))),
      ],
      selected: {value},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

/// Encabezado con el mes y flechas. Tocar el nombre vuelve al mes actual.
class MonthHeader extends StatelessWidget {
  const MonthHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    final isNow = s.month == YearMonth.now();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Mes anterior',
            onPressed: () => s.setMonth(s.month.add(-1)),
          ),
          Flexible(
            child: Tooltip(
              message: isNow ? 'Mes actual' : 'Volver al mes actual',
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: isNow ? null : () => s.setMonth(YearMonth.now()),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 170, minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(monthLabel(s.month), style: Theme.of(context).textTheme.titleMedium),
                      if (!isNow) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.today,
                            size: 18, color: Theme.of(context).colorScheme.primary),
                      ],
                    ]),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Mes siguiente',
            onPressed: () => s.setMonth(s.month.add(1)),
          ),
        ],
      ),
    );
  }
}

/// Permite cambiar de mes deslizando hacia los costados, con una animación
/// que acompaña la dirección.
class MonthSwiper extends StatefulWidget {
  const MonthSwiper({super.key, required this.child});
  final Widget child;

  @override
  State<MonthSwiper> createState() => _MonthSwiperState();
}

class _MonthSwiperState extends State<MonthSwiper> {
  YearMonth? _last;
  int _direction = 1;

  @override
  Widget build(BuildContext context) {
    final s = HouseholdScope.of(context);
    if (_last != null && _last != s.month) _direction = s.month > _last! ? 1 : -1;
    _last = s.month;
    final direction = _direction;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -250) s.setMonth(s.month.add(1));
        if (v > 250) s.setMonth(s.month.add(-1));
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, animation) {
          final incoming = child.key == ValueKey(s.month);
          final begin = Offset((incoming ? 1 : -1) * direction * 0.25, 0);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(begin: begin, end: Offset.zero).animate(animation),
              child: child,
            ),
          );
        },
        layoutBuilder: (current, previous) =>
            Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
        child: KeyedSubtree(key: ValueKey(s.month), child: widget.child),
      ),
    );
  }
}

/// Centra el contenido y limita el ancho en tablets y pantallas grandes.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: child),
      );
}

/// Monto a la derecha de un renglón, con un texto secundario opcional. Se
/// achica si no entra, para no romper el renglón con montos largos.
class TrailingAmount extends StatelessWidget {
  const TrailingAmount(this.amount, {super.key, this.detail});
  final String amount;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget fit(Widget child) =>
        FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerRight, child: child);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          fit(Text(amount, style: t.titleSmall)),
          if (detail != null)
            fit(Text(detail!,
                style: t.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}
