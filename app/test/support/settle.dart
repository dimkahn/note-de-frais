import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Laisse avancer le vrai temps (fichiers, décodage, isolates) jusqu'à disparition des
/// indicateurs de chargement, puis stabilise l'interface.
Future<void> settleRealAsync(WidgetTester tester, {int maxRounds = 60}) async {
  for (var i = 0; i < maxRounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 300));
}
