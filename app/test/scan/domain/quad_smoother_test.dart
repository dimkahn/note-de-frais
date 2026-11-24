import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/quad_smoother.dart';

void main() {
  final t0 = DateTime(2026, 3, 10, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
  final doc = Quad.inset(0.15);

  test('affiche le premier contour tel quel', () {
    final s = QuadSmoother();

    final shown = s.update(doc, at(0));

    expect(shown, doc);
  });

  test('un petit mouvement est suivi à mi-chemin (lissage du tremblement)', () {
    final s = QuadSmoother();
    s.update(doc, at(0));

    final shown = s.update(Quad.inset(0.17), at(100));

    expect(shown!.maxShift(Quad.inset(0.16)), closeTo(0, 1e-9));
  });

  test('une perte brève de la détection garde le dernier contour', () {
    final s = QuadSmoother(dropout: const Duration(milliseconds: 400));
    s.update(doc, at(0));

    final shown = s.update(null, at(400));

    expect(shown, doc);
  });

  test('une perte durable de la détection efface le contour', () {
    final s = QuadSmoother(dropout: const Duration(milliseconds: 400));
    s.update(doc, at(0));
    s.update(null, at(200));

    final shown = s.update(null, at(500));

    expect(shown, isNull);
  });

  test('un contour lointain sur une image isolée est ignoré', () {
    final s = QuadSmoother(dropout: const Duration(milliseconds: 400));
    s.update(doc, at(0));

    final shown = s.update(Quad.inset(0.3), at(100));

    expect(shown, doc);
  });

  test(
    'un contour lointain qui persiste remplace le contour, sans transition',
    () {
      final s = QuadSmoother(dropout: const Duration(milliseconds: 400));
      s.update(doc, at(0));
      s.update(Quad.inset(0.3), at(100));

      final shown = s.update(Quad.inset(0.3), at(500));

      expect(shown, Quad.inset(0.3));
    },
  );

  test(
    'des contours lointains qui changent à chaque image ne sont pas affichés',
    () {
      final s = QuadSmoother(dropout: const Duration(milliseconds: 400));
      s.update(doc, at(0));
      s.update(Quad.inset(0.3), at(100));

      expect(s.update(Quad.inset(0.4), at(500)), isNull);
      expect(s.update(Quad.inset(0.4), at(600)), Quad.inset(0.4));
    },
  );
}
