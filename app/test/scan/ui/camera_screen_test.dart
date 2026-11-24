import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
