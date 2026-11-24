import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/stability.dart';

void main() {
  final t0 = DateTime(2026, 3, 10, 12);
  DateTime at(int ms) => t0.add(Duration(milliseconds: ms));
  final doc = Quad.inset(0.15);
  final jittered = doc.withCorner(0, const Corner(0.155, 0.152));

  StabilityTracker tracker() => StabilityTracker(
    holdFor: const Duration(milliseconds: 1000),
    tolerance: 0.02,
  );

  test('déclenche quand le contour reste stable assez longtemps', () {
    final t = tracker();

    expect(t.update(doc, at(0)), isFalse);
    expect(t.update(jittered, at(500)), isFalse);
    expect(t.update(doc, at(1000)), isTrue);
  });

  test('un mouvement important relance l\'attente', () {
    final t = tracker();
    t.update(doc, at(0));

    t.update(Quad.inset(0.3), at(600));

    expect(t.update(Quad.inset(0.3), at(1200)), isFalse);
    expect(t.update(Quad.inset(0.3), at(1600)), isTrue);
  });

  test(
    'une image aberrante isolée (autre contour) ne relance pas l\'attente',
    () {
      final t = tracker();
      t.update(doc, at(0));
      t.update(doc, at(200));

      t.update(Quad.inset(0.3), at(300));

      expect(t.update(doc, at(1000)), isTrue);
    },
  );

  test('après une perte durable, l\'attente repart de zéro', () {
    final t = tracker();
    t.update(doc, at(0));
    t.update(Quad.inset(0.3), at(100));
    t.update(null, at(1000));

    expect(t.update(Quad.inset(0.3), at(1500)), isFalse);
    expect(t.update(Quad.inset(0.3), at(2000)), isFalse);
  });

  test('la perte durable du document relance l\'attente', () {
    final t = StabilityTracker(
      holdFor: const Duration(milliseconds: 1000),
      tolerance: 0.02,
      dropout: const Duration(milliseconds: 300),
    );
    t.update(doc, at(0));

    t.update(null, at(500));

    expect(t.update(doc, at(1000)), isFalse);
  });

  test(
    'une perte brève du document (image floue) ne relance pas l\'attente',
    () {
      final t = StabilityTracker(
        holdFor: const Duration(milliseconds: 1000),
        tolerance: 0.02,
        dropout: const Duration(milliseconds: 300),
      );
      t.update(doc, at(0));
      t.update(null, at(200));

      expect(t.update(jittered, at(1000)), isTrue);
    },
  );

  test('pendant une perte brève, ni déclenchement ni progression', () {
    final t = tracker();
    t.update(doc, at(0));
    t.update(doc, at(200));

    expect(t.update(null, at(500)), isFalse);
    expect(t.progress, closeTo(0.2, 1e-9));
  });

  test('un mouvement important après une perte brève relance l\'attente', () {
    final t = tracker();
    t.update(doc, at(0));
    t.update(null, at(200));

    t.update(Quad.inset(0.3), at(400));

    expect(t.update(Quad.inset(0.3), at(1000)), isFalse);
    expect(t.update(Quad.inset(0.3), at(1400)), isTrue);
  });

  test('par défaut, tolère une perte de 400 ms', () {
    final t = StabilityTracker(holdFor: const Duration(milliseconds: 1000));
    t.update(doc, at(0));
    t.update(null, at(400));

    expect(t.update(doc, at(1000)), isTrue);
  });

  test('ne déclenche qu\'une fois jusqu\'à la réinitialisation', () {
    final t = tracker();
    t.update(doc, at(0));
    expect(t.update(doc, at(1000)), isTrue);

    expect(t.update(doc, at(2500)), isFalse);

    t.reset();
    t.update(doc, at(3000));
    expect(t.update(doc, at(4000)), isTrue);
  });

  test('expose la progression pour l\'animation', () {
    final t = tracker();
    t.update(doc, at(0));
    t.update(doc, at(250));

    expect(t.progress, closeTo(0.25, 1e-9));
  });
}
