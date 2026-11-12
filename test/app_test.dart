import 'package:flutter_test/flutter_test.dart';
import 'package:gastos_pareja/data/memory_repository.dart';
import 'package:gastos_pareja/main.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('modo demo: navega las pestañas y carga un gasto', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
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
    await tester.enterText(find.byType(TextFormField).first, '1.500');
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
    expect(find.text('Privacidad de tus gastos personales'), findsOneWidget);
    expect(find.text('Elegir en cada gasto'), findsOneWidget);
  });
}
