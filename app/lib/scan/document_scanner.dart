import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../domain/expense.dart';
import '../domain/quad.dart';

/// Détection du contour, redressement et filtres, sur l'appareil (hors-ligne).
///
/// Même algorithme et mêmes paramètres que `server/.../imaging/OpenCvImageProcessor.java` :
/// les garder alignés. Fonctions synchrones et sans état : à appeler via `Isolate.run`.
final class DocumentScanner {
  const DocumentScanner();

  static const _detectionMaxSide = 800;

  /// Taille maximale des images du flux caméra analysées en direct : assez pour trouver le contour,
  /// assez petit pour ne copier que quelques centaines de Ko par image.
  static const liveMaxSide = _detectionMaxSide ~/ 2;
  static const _minAreaRatio = 0.10;
  static const _maxAreaRatio = 0.98;
  static const _jpegQuality = 90;

  /// Contour du document dans une image encodée (JPEG/PNG), orientation EXIF appliquée.
  Quad? detect(Uint8List encoded) {
    final src = cv.imdecode(encoded, cv.IMREAD_GRAYSCALE);
    try {
      if (src.isEmpty) return null;
      final scale = math.min(
        1.0,
        _detectionMaxSide / math.max(src.rows, src.cols),
      );
      final small = scale < 1
          ? cv.resize(src, (
              (src.cols * scale).round(),
              (src.rows * scale).round(),
            ), interpolation: cv.INTER_AREA)
          : src.clone();
      try {
        return _detectInGray(small);
      } finally {
        small.dispose();
      }
    } finally {
      src.dispose();
    }
  }

  /// Contour dans un plan de luminance brut (plan Y du flux caméra), dans le repère du capteur.
  Quad? detectInLuma(
    Uint8List plane, {
    required int width,
    required int height,
    required int bytesPerRow,
  }) {
    final (small, w, h) = downsampleLuma(
      plane,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      maxSide: liveMaxSide,
    );
    final gray = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, small);
    try {
      return _detectInGray(gray);
    } finally {
      gray.dispose();
    }
  }

  /// Redresse [encoded] selon [quad] puis applique [filter] ; renvoie un JPEG.
  Uint8List render(
    Uint8List encoded,
    Quad quad,
    ImageFilter filter, {
    int maxSide = 2400,
  }) {
    final src = cv.imdecode(encoded, cv.IMREAD_COLOR);
    if (src.isEmpty) throw ArgumentError('Image illisible');
    final mats = <cv.Mat>[src];
    try {
      final warped = _track(mats, _warp(src, quad));
      final factor = math.min(
        1.0,
        maxSide / math.max(warped.cols, warped.rows),
      );
      final sized = factor < 1
          ? _track(
              mats,
              cv.resize(warped, (
                (warped.cols * factor).round(),
                (warped.rows * factor).round(),
              ), interpolation: cv.INTER_AREA),
            )
          : warped;
      final filtered = _track(mats, _applyFilter(sized, filter, mats));
      final (_, jpeg) = cv.imencode(
        '.jpg',
        filtered,
        params: cv.VecI32.fromList([cv.IMWRITE_JPEG_QUALITY, _jpegQuality]),
      );
      return jpeg;
    } finally {
      for (final m in mats) {
        m.dispose();
      }
    }
  }

  // --- Détection ---

  Quad? _detectInGray(cv.Mat gray) {
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);
    final (otsu, binary) = cv.threshold(
      blurred,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    final edges = cv.canny(blurred, otsu * 0.5, otsu);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    final dilated = cv.dilate(edges, kernel);
    final (contours, hierarchy) = cv.findContours(
      dilated,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );
    try {
      final imageArea = (gray.rows * gray.cols).toDouble();
      final sorted = contours.toList()
        ..sort((a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)));
      for (final contour in sorted.take(5)) {
        final approx = cv.approxPolyDP(
          contour,
          0.02 * cv.arcLength(contour, true),
          true,
        );
        try {
          if (approx.length != 4 || !cv.isContourConvex(approx)) continue;
          final ratio = cv.contourArea(approx) / imageArea;
          if (ratio < _minAreaRatio || ratio > _maxAreaRatio) continue;
          return Quad.fromUnordered([
            for (final p in approx.toList())
              Corner(p.x / gray.cols, p.y / gray.rows),
          ]);
        } finally {
          approx.dispose();
        }
      }
      return null;
    } finally {
      for (final m in [blurred, binary, edges, kernel, dilated]) {
        m.dispose();
      }
      contours.dispose();
      hierarchy.dispose();
    }
  }

  // --- Redressement ---

  cv.Mat _warp(cv.Mat src, Quad quad) {
    final px = [for (final c in quad.corners) (c.x * src.cols, c.y * src.rows)];
    double dist((double, double) a, (double, double) b) =>
        math.sqrt(math.pow(a.$1 - b.$1, 2) + math.pow(a.$2 - b.$2, 2));
    final width = math.max(dist(px[0], px[1]), dist(px[3], px[2])).round();
    final height = math.max(dist(px[0], px[3]), dist(px[1], px[2])).round();
    final from = cv.VecPoint2f.fromList([
      for (final (x, y) in px) cv.Point2f(x, y),
    ]);
    final to = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(width - 1, 0),
      cv.Point2f(width - 1, height - 1),
      cv.Point2f(0, height - 1),
    ]);
    final m = cv.getPerspectiveTransform2f(from, to);
    try {
      return cv.warpPerspective(src, m, (width, height), flags: cv.INTER_CUBIC);
    } finally {
      m.dispose();
      from.dispose();
      to.dispose();
    }
  }

  // --- Filtres (cf. ImageFilter côté serveur) ---

  cv.Mat _applyFilter(cv.Mat src, ImageFilter filter, List<cv.Mat> mats) =>
      switch (filter) {
        ImageFilter.none => src.clone(),
        ImageFilter.enhance => _unsharp(
          _track(mats, _claheOnLightness(src, mats)),
          1.0,
          1.5,
          mats,
        ),
        ImageFilter.sharpen => _unsharp(src, 1.5, 2.0, mats),
        ImageFilter.scanBw => _scanBlackAndWhite(src, mats),
      };

  cv.Mat _claheOnLightness(cv.Mat src, List<cv.Mat> mats) {
    final lab = _track(mats, cv.cvtColor(src, cv.COLOR_BGR2Lab));
    final channels = cv.split(lab);
    final clahe = cv.CLAHE.create(2.0, (8, 8));
    try {
      final l = clahe.apply(channels[0]);
      final merged = _track(
        mats,
        cv.merge(cv.VecMat.fromList([l, channels[1], channels[2]])),
      );
      l.dispose();
      return cv.cvtColor(merged, cv.COLOR_Lab2BGR);
    } finally {
      clahe.dispose();
      channels.dispose();
    }
  }

  cv.Mat _unsharp(cv.Mat src, double sigma, double amount, List<cv.Mat> mats) {
    final blurred = _track(mats, cv.gaussianBlur(src, (0, 0), sigma));
    return cv.addWeighted(src, 1 + amount, blurred, -amount, 0);
  }

  cv.Mat _scanBlackAndWhite(cv.Mat src, List<cv.Mat> mats) {
    final gray = _track(mats, cv.cvtColor(src, cv.COLOR_BGR2GRAY));
    final block = math.max(15, (math.min(gray.cols, gray.rows) ~/ 30) | 1);
    return cv.adaptiveThreshold(
      gray,
      255,
      cv.ADAPTIVE_THRESH_GAUSSIAN_C,
      cv.THRESH_BINARY,
      block,
      12,
    );
  }

  static cv.Mat _track(List<cv.Mat> mats, cv.Mat m) {
    mats.add(m);
    return m;
  }
}

/// Détection dans un isolate, sur une luminance déjà réduite (sans pas de ligne).
///
/// Fonction de premier niveau à dessein : la fermeture envoyée à l'isolate ne peut capturer que
/// ses paramètres. Créée dans une méthode de l'écran caméra, elle emportait l'état de l'écran et le
/// `CameraController`, que `Isolate.run` refuse d'envoyer (« object is unsendable ») : la détection
/// en direct échouait à chaque image.
Future<Quad?> detectInBackground(
  Uint8List luma, {
  required int width,
  required int height,
}) => Isolate.run(
  () => const DocumentScanner().detectInLuma(
    luma,
    width: width,
    height: height,
    bytesPerRow: width,
  ),
);

/// Réduit un plan de luminance (avec pas de ligne éventuel) à [maxSide] pixels au plus, par
/// échantillonnage : rapide et suffisant pour la détection en direct.
(Uint8List, int, int) downsampleLuma(
  Uint8List plane, {
  required int width,
  required int height,
  required int bytesPerRow,
  required int maxSide,
}) {
  final step = math.max(1, (math.max(width, height) / maxSide).ceil());
  final w = width ~/ step, h = height ~/ step;
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * step * bytesPerRow;
    for (var x = 0; x < w; x++) {
      out[y * w + x] = plane[row + x * step];
    }
  }
  return (out, w, h);
}
