import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/data/memory_repository.dart';
import 'package:gastos_pareja/main.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('modo demo: navega las pestañas y carga un gasto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(600, 1000));
    final repo = MemoryRepository(withDemoData: true);
    await tester.pumpWidget(GastosApp(repo: repo, demo: true));
    await tester.pumpAndSettle();

    expect(find.text('Saldo entre ustedes'), findsOneWidget);
    // El regalo privado de Juan no se ve desde la cuenta de Ana.
    await tester.tap(find.text('Movimientos').last);
    await tester.pumpAndSettle();
    expect(find.text('Supermercado semanal'), findsOneWidget);
    expect(find.text('Regalo sorpresa'), findsNothing);

    // Cargar un gasto nuevo.
    await tester.tap(find.text('Gasto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '200000');
    // El monto se formatea solo mientras se escribe.
    expect(find.text('200.000'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'Descripción (opcional)'), 'Farmacia');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Farmacia'), findsOneWidget);

    // Juan sí ve su regalo privado.
    await tester.tap(find.textContaining('Ver como'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimientos').last);
    await tester.pumpAndSettle();
    expect(find.text('Regalo sorpresa'), findsOneWidget);

    for (final tab in ['Planificación', 'Ajustes']) {
      await tester.tap(find.text(tab).last);
      await tester.pumpAndSettle();
    }
    // Ajustes: tema oscuro y sin centavos.
    expect(find.text('Oscuro'), findsOneWidget);
    await tester.tap(find.text('Oscuro'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Oscuro'))).brightness, Brightness.dark);

    await tester.scrollUntilVisible(find.text('Mostrar centavos'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('200.000,50'), findsOneWidget);
    await tester.tap(find.text('Mostrar centavos'));
    await tester.pumpAndSettle();
    expect(find.textContaining('200.000,50'), findsNothing);

    await tester.scrollUntilVisible(find.text('Elegir en cada gasto'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Privacidad de tus gastos personales'), findsOneWidget);

    // Deslizar hacia el costado cambia de mes.
    await tester.tap(find.text('Resumen').last);
    await tester.pumpAndSettle();
    final month = tester.widget<Text>(find.textContaining(RegExp(r'^[A-Z][a-z]+ \d{4}$'))).data;
    await tester.fling(find.text('Saldo entre ustedes'), const Offset(-300, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text(month!), findsNothing);
  });
}
