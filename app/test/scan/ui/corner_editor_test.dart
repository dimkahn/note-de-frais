import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/ui/corner_editor.dart';

void main() {
  // Zone d'édition de 400 x 600 px pour une image de même proportion (2:3).
  Future<List<Quad>> pumpEditor(WidgetTester tester, Quad initial) async {
    final changes = <Quad>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: CornerEditor(
              imageAspectRatio: 2 / 3,
              quad: initial,
              onChanged: changes.add,
              child: const ColoredBox(color: Colors.grey),
            ),
          ),
        ),
      ),
    );
    return changes;
  }

  testWidgets('affiche une poignée accessible par coin', (tester) async {
    await pumpEditor(tester, Quad.inset(0.1));

    expect(find.bySemanticsLabel(RegExp('Coin')), findsNWidgets(4));
    final size = tester.getSize(find.byKey(const ValueKey('corner-0')));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('glisser une poignée déplace le coin correspondant', (
    tester,
  ) async {
    final changes = await pumpEditor(tester, Quad.inset(0.1));

    await tester.drag(
      find.byKey(const ValueKey('corner-0')),
      const Offset(40, 60),
    );
    await tester.pump();

    final last = changes.last;
    expect(last.topLeft.x, closeTo(0.2, 0.02));
    expect(last.topLeft.y, closeTo(0.2, 0.02));
    expect(last.bottomRight, Quad.inset(0.1).bottomRight);
  });

  testWidgets('un coin ne sort pas de l\'image', (tester) async {
    final changes = await pumpEditor(tester, Quad.inset(0.1));

    await tester.drag(
      find.byKey(const ValueKey('corner-2')),
      const Offset(500, 500),
    );
    await tester.pump();

    expect(changes.last.bottomRight, const Corner(1, 1));
  });
}
