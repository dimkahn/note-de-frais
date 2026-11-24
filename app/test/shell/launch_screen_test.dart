import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/shell/launch_screen.dart';

void main() {
  Widget gate(Future<String> load) => MaterialApp(
    home: LaunchGate<String>(
      load: load,
      minDuration: const Duration(milliseconds: 1200),
      builder: (value) => Text('app: $value'),
    ),
  );

  testWidgets('affiche le nom de l\'application pendant le chargement', (
    tester,
  ) async {
    await tester.pumpWidget(gate(Completer<String>().future));

    expect(find.text('Note de frais'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // durée minimale écoulée
  });

  testWidgets(
    'reste affiché au moins la durée minimale, puis ouvre l\'application',
    (tester) async {
      await tester.pumpWidget(gate(Future.value('prête')));

      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('app: prête'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('app: prête'), findsOneWidget);
      expect(find.text('Note de frais'), findsNothing);
    },
  );

  testWidgets('attend la fin d\'un chargement plus long que le minimum', (
    tester,
  ) async {
    final loading = Completer<String>();
    await tester.pumpWidget(gate(loading.future));

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Note de frais'), findsOneWidget);

    loading.complete('prête');
    await tester.pumpAndSettle();
    expect(find.text('app: prête'), findsOneWidget);
  });

  testWidgets('montre l\'erreur si le démarrage échoue', (tester) async {
    final loading = Completer<String>();
    await tester.pumpWidget(gate(loading.future));

    loading.completeError(StateError('base illisible'));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.textContaining('Démarrage impossible'), findsOneWidget);
    expect(find.textContaining('base illisible'), findsOneWidget);
  });
}
