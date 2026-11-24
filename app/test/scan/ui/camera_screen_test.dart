import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/scan_session.dart';
import 'package:note_de_frais/scan/ui/camera_screen.dart';

import '../../support/settle.dart';

void main() {
  testWidgets('sans caméra, propose de choisir une image', (tester) async {
    // En test, aucun plugin caméra n'est disponible : même cas qu'un appareil sans caméra
    // ou une permission refusée.
    await tester.pumpWidget(const MaterialApp(home: CameraScreen()));
    await settleRealAsync(tester);

    expect(find.textContaining('Caméra indisponible'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Choisir une image'),
      findsOneWidget,
    );
  });

  testWidgets('le carrousel propose Ticket et Document et change de mode', (
    tester,
  ) async {
    ScanMode? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanModeSelector(
            mode: ScanMode.ticket,
            onChanged: (m) => chosen = m,
          ),
        ),
      ),
    );

    await tester.tap(find.text('Document'));

    expect(find.text('Ticket'), findsOneWidget);
    expect(chosen, ScanMode.document);
  });

  testWidgets('le carrousel se change aussi en glissant', (tester) async {
    ScanMode? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScanModeSelector(
            mode: ScanMode.document,
            onChanged: (m) => chosen = m,
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ScanModeSelector), const Offset(300, 0));

    expect(chosen, ScanMode.ticket);
  });

  testWidgets('un mode imposé ne se change pas', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScanModeSelector(mode: ScanMode.document, onChanged: null),
        ),
      ),
    );

    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Ticket'), findsNothing);
  });

  testWidgets('la pile montre le nombre de pages prises et ouvre la revue', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageStack(
            photoPaths: const ['/a.jpg', '/b.jpg', '/c.jpg'],
            onTap: () => opened = true,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(PageStack));

    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('3 pages prises, revoir'), findsOneWidget);
    expect(opened, isTrue);
  });
}
