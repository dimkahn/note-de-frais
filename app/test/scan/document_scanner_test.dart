import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/domain/expense.dart';
import 'package:note_de_frais/domain/quad.dart';
import 'package:note_de_frais/scan/document_scanner.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Photo synthétique : ticket clair (avec lignes de « texte ») posé sur une table sombre.
Uint8List photoOfReceipt(int w, int h, List<(int, int)> corners) {
  final img = cv.Mat.fromScalar(
    h,
    w,
    cv.MatType.CV_8UC3,
    cv.Scalar(30, 35, 45),
  );
  final poly = cv.VecVecPoint.fromList([
    [for (final (x, y) in corners) cv.Point(x, y)],
  ]);
  cv.fillPoly(img, poly, cv.Scalar(225, 232, 235));
  final (x0, y0) = corners.first;
  for (var y = y0 + 60; y < y0 + 400; y += 40) {
    cv.rectangle(
      img,
      cv.Rect(x0 + 60, y, 220, 10),
      cv.Scalar(90, 90, 90),
      thickness: -1,
    );
  }
  final (_, bytes) = cv.imencode('.jpg', img);
  img.dispose();
  return bytes;
}

/// Photo réaliste sur fond clair : éclairage en dégradé, bruit de capteur, ticket peu contrasté.
Uint8List photoOnLightBackground(
  int w,
  int h,
  List<(int, int)> corners, {
  required cv.Scalar background,
  required cv.Scalar paper,
}) {
  final img = cv.Mat.fromScalar(h, w, cv.MatType.CV_8UC3, background);
  final poly = cv.VecVecPoint.fromList([
    [for (final (x, y) in corners) cv.Point(x, y)],
  ]);
  cv.fillPoly(img, poly, paper);
  final (x0, y0) = corners.first;
  for (var y = y0 + 60; y < y0 + 400; y += 40) {
    cv.rectangle(
      img,
      cv.Rect(x0 + 60, y, 220, 10),
      cv.Scalar(90, 90, 90),
      thickness: -1,
    );
  }
  // Éclairage : plus sombre d'un côté (ombre douce), comme sous une lampe.
  final shade = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  for (var x = 0; x < w; x += 4) {
    final v = (x / w * 40).round();
    cv.rectangle(
      shade,
      cv.Rect(x, 0, 4, h),
      cv.Scalar(v.toDouble(), v.toDouble(), v.toDouble()),
      thickness: -1,
    );
  }
  final lit = cv.subtract(img, shade);
  final noise = cv.Mat.zeros(h, w, cv.MatType.CV_8UC3);
  cv.randn(noise, cv.Scalar.all(0), cv.Scalar.all(6));
  final noisy = cv.add(lit, noise);
  final (_, bytes) = cv.imencode('.jpg', noisy);
  for (final m in [img, shade, lit, noise, noisy]) {
    m.dispose();
  }
  return bytes;
}

Uint8List uniform(int w, int h) {
  final img = cv.Mat.fromScalar(
    h,
    w,
    cv.MatType.CV_8UC3,
    cv.Scalar(200, 200, 200),
  );
  final (_, bytes) = cv.imencode('.jpg', img);
  return bytes;
}

(int, int) sizeOf(Uint8List jpeg) {
  final m = cv.imdecode(jpeg, cv.IMREAD_COLOR);
  final size = (m.cols, m.rows);
  m.dispose();
  return size;
}

void main() {
  const scanner = DocumentScanner();
  // Ticket légèrement de travers dans une photo 1000 x 1400.
  const receiptCorners = [(240, 210), (780, 250), (760, 1210), (220, 1180)];

  group('détection', () {
    test('trouve les 4 coins d\'un ticket photographié de travers', () {
      final quad = scanner.detect(photoOfReceipt(1000, 1400, receiptCorners));

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(0.24, 0.02));
      expect(quad.topLeft.y, closeTo(0.15, 0.02));
      expect(quad.bottomRight.x, closeTo(0.76, 0.02));
      expect(quad.bottomRight.y, closeTo(0.864, 0.02));
    });

    test(
      'ignore un grand objet clair arrondi à côté du ticket (main, assiette)',
      () {
        final img = cv.imdecode(
          photoOfReceipt(1400, 1400, const [
            (200, 300),
            (560, 320),
            (540, 1100),
            (180, 1080),
          ]),
          cv.IMREAD_COLOR,
        );
        cv.ellipse(
          img,
          cv.Point(1050, 700),
          cv.Point(330, 520),
          15,
          0,
          360,
          cv.Scalar(200, 210, 225),
          thickness: -1,
        );
        final (_, photo) = cv.imencode('.jpg', img);
        img.dispose();

        final quad = scanner.detect(photo);

        expect(quad, isNotNull);
        expect(quad!.topLeft.x, closeTo(200 / 1400, 0.03));
        expect(quad.bottomRight.x, closeTo(540 / 1400, 0.03));
      },
    );

    test('photo réelle : ticket crème posé sur une feuille blanche', () {
      // Aperçu caméra capturé sur un téléphone (Android 16) : très peu de contraste, la feuille
      // dépasse du cadre ; c'est le ticket qu'il faut trouver, pas la feuille.
      final photo = File('test/fixtures/ticket_sur_feuille_blanche.jpg')
          .readAsBytesSync();

      final quad = scanner.detect(photo);

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(0.35, 0.04));
      expect(quad.topLeft.y, closeTo(0.088, 0.04));
      expect(quad.topRight.x, closeTo(0.845, 0.04));
      expect(quad.bottomRight.y, closeTo(0.916, 0.04));
      expect(quad.bottomLeft.x, closeTo(0.305, 0.04));
    });

    test(
      'flux caméra (Y + U) : trouve le ticket crème sur feuille blanche',
      () async {
        final bgr = cv.imdecode(
          File('test/fixtures/ticket_sur_feuille_blanche.jpg')
              .readAsBytesSync(),
          cv.IMREAD_COLOR,
        );
        final ycrcb = cv.split(cv.cvtColor(bgr, cv.COLOR_BGR2YCrCb));
        final y = ycrcb[0], cb = ycrcb[2];
        // Le plan U d'un flux YUV 4:2:0 est à demi-résolution.
        final u = cv.resize(cb, (
          bgr.cols ~/ 2,
          bgr.rows ~/ 2,
        ), interpolation: cv.INTER_AREA);
        final (luma, w, h) = downsampleLuma(
          Uint8List.fromList(y.data),
          width: bgr.cols,
          height: bgr.rows,
          bytesPerRow: bgr.cols,
          maxSide: DocumentScanner.liveMaxSide,
        );
        final chroma = sampleChroma(
          Uint8List.fromList(u.data),
          lumaWidth: bgr.cols,
          lumaHeight: bgr.rows,
          bytesPerRow: u.cols,
          pixelStride: 1,
          width: w,
          height: h,
        );

        final quad = await detectInBackground(
          luma,
          width: w,
          height: h,
          blueChroma: chroma,
        );

        expect(quad, isNotNull);
        expect(quad!.topLeft.x, closeTo(0.35, 0.05));
        expect(quad.bottomRight.y, closeTo(0.916, 0.05));
      },
    );

    test(
      'trouve un ticket dont un coin chevauche un objet sombre (clavier)',
      () {
        // Bureau en bois, clavier noir en haut ; le coin haut-gauche du ticket est posé dessus :
        // les bords du ticket et du clavier se touchent.
        final img = cv.Mat.fromScalar(
          1400,
          1000,
          cv.MatType.CV_8UC3,
          cv.Scalar(40, 75, 120),
        );
        cv.rectangle(
          img,
          cv.Rect(-50, 30, 1000, 300),
          cv.Scalar(25, 25, 25),
          thickness: -1,
        );
        final receipt = cv.VecVecPoint.fromList([
          [
            cv.Point(290, 220),
            cv.Point(750, 250),
            cv.Point(740, 1250),
            cv.Point(250, 1230),
          ],
        ]);
        cv.fillPoly(img, receipt, cv.Scalar(232, 236, 238));
        for (var y = 420; y < 1100; y += 50) {
          cv.rectangle(
            img,
            cv.Rect(330, y, 300, 12),
            cv.Scalar(90, 90, 90),
            thickness: -1,
          );
        }
        final (_, photo) = cv.imencode('.jpg', img);
        img.dispose();

        final quad = scanner.detect(photo);

        expect(quad, isNotNull);
        expect(quad!.topLeft.x, closeTo(0.29, 0.03));
        expect(quad.topLeft.y, closeTo(220 / 1400, 0.03));
        expect(quad.bottomRight.x, closeTo(0.74, 0.03));
        expect(quad.bottomRight.y, closeTo(1250 / 1400, 0.03));
      },
    );

    test('trouve un ticket blanc posé sur du bois clair', () {
      final quad = scanner.detect(
        photoOnLightBackground(
          1000,
          1400,
          receiptCorners,
          background: cv.Scalar(150, 190, 215),
          paper: cv.Scalar(238, 242, 245),
        ),
      );

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(0.24, 0.02));
      expect(quad.bottomRight.y, closeTo(0.864, 0.02));
    });

    test('trouve un ticket blanc posé sur une table blanche', () {
      final quad = scanner.detect(
        photoOnLightBackground(
          1000,
          1400,
          receiptCorners,
          background: cv.Scalar(212, 214, 216),
          paper: cv.Scalar(245, 246, 247),
        ),
      );

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(0.24, 0.02));
      expect(quad.bottomRight.y, closeTo(0.864, 0.02));
    });

    test('n\'invente pas de contour sur un fond clair sans document', () {
      // Ticket de la couleur exacte du fond : seuls restent le dégradé et le bruit.
      final quad = scanner.detect(
        photoOnLightBackground(
          1000,
          1400,
          const [(0, 0), (1, 0), (1, 1), (0, 1)],
          background: cv.Scalar(212, 214, 216),
          paper: cv.Scalar(212, 214, 216),
        ),
      );

      expect(quad, isNull);
    });

    test('ne trouve rien sur une image uniforme', () {
      expect(scanner.detect(uniform(800, 600)), isNull);
    });

    test(
      'détecte en arrière-plan sur la luminance réduite du flux caméra',
      () async {
        final m = cv.imdecode(
          photoOfReceipt(1000, 1400, receiptCorners),
          cv.IMREAD_GRAYSCALE,
        );
        final (small, w, h) = downsampleLuma(
          Uint8List.fromList(m.data),
          width: m.cols,
          height: m.rows,
          bytesPerRow: m.cols,
          maxSide: DocumentScanner.liveMaxSide,
        );

        final quad = await detectInBackground(small, width: w, height: h);

        expect(quad, isNotNull);
        expect(quad!.topLeft.x, closeTo(0.24, 0.03));
      },
    );

    test('détecte aussi sur une image de luminance brute (flux caméra)', () {
      final m = cv.imdecode(
        photoOfReceipt(1000, 1400, receiptCorners),
        cv.IMREAD_GRAYSCALE,
      );
      final luma = Uint8List.fromList(m.data);

      final quad = scanner.detectInLuma(
        luma,
        width: m.cols,
        height: m.rows,
        bytesPerRow: m.cols,
      );

      expect(quad, isNotNull);
      expect(quad!.topLeft.x, closeTo(0.24, 0.03));
    });
  });

  group('rendu', () {
    test('redresse le ticket selon les coins choisis', () {
      final quad = Quad.parse('0.25,0.25,0.75,0.25,0.75,0.75,0.25,0.75');

      final jpeg = scanner.render(uniform(1000, 800), quad, ImageFilter.none);

      final (w, h) = sizeOf(jpeg);
      expect(w, inInclusiveRange(495, 505));
      expect(h, inInclusiveRange(395, 405));
    });

    test('chaque filtre produit une image valide', () {
      final photo = photoOfReceipt(1000, 1400, receiptCorners);
      final quad = scanner.detect(photo)!;

      for (final filter in ImageFilter.values) {
        expect(
          sizeOf(scanner.render(photo, quad, filter)).$1,
          greaterThan(400),
          reason: filter.name,
        );
      }
    });

    test('limite la taille de l\'aperçu', () {
      final jpeg = scanner.render(
        uniform(3000, 2000),
        Quad.inset(0),
        ImageFilter.none,
        maxSide: 600,
      );

      expect(sizeOf(jpeg), (600, 400));
    });
  });

  test('sous-échantillonne la luminance en tenant compte du pas de ligne', () {
    // 4 x 2 pixels utiles, 6 octets par ligne (2 octets de bourrage).
    final plane = Uint8List.fromList([1, 2, 3, 4, 0, 0, 5, 6, 7, 8, 0, 0]);

    final (small, w, h) = downsampleLuma(
      plane,
      width: 4,
      height: 2,
      bytesPerRow: 6,
      maxSide: 2,
    );

    expect((w, h), (2, 1));
    expect(small, [1, 3]);
  });

  test('échantillonne la chrominance entrelacée (NV12 / pas de pixel 2) à la taille de la luminance', () {
    // Luminance 4 x 4, chrominance 2 x 2 entrelacée U,V : U = 10, 20 / 30, 40.
    final plane = Uint8List.fromList([10, 99, 20, 99, 30, 99, 40, 99]);

    final out = sampleChroma(
      plane,
      lumaWidth: 4,
      lumaHeight: 4,
      bytesPerRow: 4,
      pixelStride: 2,
      width: 2,
      height: 2,
    );

    expect(out, [10, 20, 30, 40]);
  });
}
