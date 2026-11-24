import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/scan/domain/quad.dart';

void main() {
  const square = Quad(
    Corner(0.2, 0.2),
    Corner(0.8, 0.2),
    Corner(0.8, 0.8),
    Corner(0.2, 0.8),
  );

  group('format', () {
    test('aller-retour avec le format texte partagé avec le serveur', () {
      final q = Quad.parse('0.1,0.2,0.9,0.15,0.95,0.9,0.05,0.85');

      expect(q.format(), '0.1,0.2,0.9,0.15,0.95,0.9,0.05,0.85');
      expect(Quad.parse(q.format()), q);
    });

    test('refuse un texte invalide', () {
      expect(() => Quad.parse('0.1,0.2'), throwsFormatException);
      expect(() => Quad.parse('a,0,1,0,1,1,0,1'), throwsFormatException);
    });
  });

  group('géométrie', () {
    test(
      'remet dans l\'ordre haut-gauche, haut-droit, bas-droit, bas-gauche',
      () {
        final q = Quad.fromUnordered(const [
          Corner(0.8, 0.8),
          Corner(0.2, 0.2),
          Corner(0.2, 0.8),
          Corner(0.8, 0.2),
        ]);

        expect(q, square);
      },
    );

    test('reconnaît un quadrilatère convexe', () {
      expect(square.isConvex, isTrue);
      expect(
        const Quad(
          Corner(0, 0),
          Corner(1, 1),
          Corner(1, 0),
          Corner(0, 1),
        ).isConvex,
        isFalse,
      );
    });

    test('calcule l\'aire normalisée', () {
      expect(square.area, closeTo(0.36, 1e-9));
    });

    test('mesure le plus grand déplacement entre deux contours', () {
      final moved = square.withCorner(2, const Corner(0.83, 0.84));

      expect(square.maxShift(moved), closeTo(0.05, 1e-9));
    });
  });

  group('déplacement d\'un coin', () {
    test('déplace le coin demandé', () {
      final q = square.moveCorner(0, const Corner(0.1, 0.15));

      expect(q.topLeft, const Corner(0.1, 0.15));
    });

    test('garde le coin dans l\'image', () {
      final q = square.moveCorner(1, const Corner(1.4, -0.3));

      expect(q.topRight, const Corner(1, 0));
    });

    test('refuse un déplacement qui rendrait le contour croisé', () {
      final q = square.moveCorner(0, const Corner(0.9, 0.9));

      expect(q, square);
    });
  });

  group('orientation du capteur', () {
    test(
      'une rotation de 90° ramène le contour dans le repère de l\'écran',
      () {
        // Image capteur paysage : document dans la moitié gauche.
        const sensor = Quad(
          Corner(0.1, 0.2),
          Corner(0.5, 0.2),
          Corner(0.5, 0.8),
          Corner(0.1, 0.8),
        );

        final screen = sensor.rotated(90);

        expect(screen.topLeft.x, closeTo(0.2, 1e-9));
        expect(screen.topLeft.y, closeTo(0.1, 1e-9));
        expect(screen.bottomRight.x, closeTo(0.8, 1e-9));
        expect(screen.bottomRight.y, closeTo(0.5, 1e-9));
        expect(screen.isConvex, isTrue);
      },
    );

    test('0° ne change rien', () {
      expect(square.rotated(0), square);
    });
  });

  test('cadre par défaut légèrement en retrait des bords', () {
    final q = Quad.inset(0.1);

    expect(q.topLeft, const Corner(0.1, 0.1));
    expect(q.bottomRight, const Corner(0.9, 0.9));
  });
}
