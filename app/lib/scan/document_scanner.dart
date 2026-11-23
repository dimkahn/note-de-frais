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
  static const _approxTolerances = [0.02, 0.03, 0.05];

  /// Écart maximal entre l'aire du contour et celle du quadrilatère retenu (15 %).
  static const _maxFillGap = 0.15;
  static const _weakClaheClip = 3.0;
  static const _weakCannyLow = 20.0;
  static const _weakCannyHigh = 60.0;

  /// Un coin à moins de 2 % du bord de l'image est considéré « sur le bord ».
  static const _borderMargin = 0.02;

  /// Contours examinés par passe (les plus grands).
  static const _maxCandidates = 10;

  /// Écart minimal de teinte (canal b de Lab) pour tenter la passe couleur.
  static const _minWarmthRange = 6.0;

  /// Contour du document dans une image encodée (JPEG/PNG), orientation EXIF appliquée.
  Quad? detect(Uint8List encoded) {
    final src = cv.imdecode(encoded, cv.IMREAD_COLOR);
    if (src.isEmpty) {
      src.dispose();
      return null;
    }
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
    final gray = cv.cvtColor(small, cv.COLOR_BGR2GRAY);
    final lab = cv.cvtColor(small, cv.COLOR_BGR2Lab);
    final channels = cv.split(lab);
    try {
      return _detectIn(gray, warmth: channels[2]);
    } finally {
      channels.dispose();
      for (final m in [src, small, gray, lab]) {
        m.dispose();
      }
    }
  }

  /// Contour dans un plan de luminance brut (plan Y du flux caméra), dans le repère du capteur.
  /// [blueChroma] : plan U (Cb) déjà échantillonné à la taille réduite de la luminance
  /// (cf. [sampleChroma]) ; il permet la passe couleur (papier crème sur feuille blanche).
  Quad? detectInLuma(
    Uint8List plane, {
    required int width,
    required int height,
    required int bytesPerRow,
    Uint8List? blueChroma,
  }) {
    final (small, w, h) = downsampleLuma(
      plane,
      width: width,
      height: height,
      bytesPerRow: bytesPerRow,
      maxSide: liveMaxSide,
    );
    final gray = cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, small);
    final cb = blueChroma != null && blueChroma.length == w * h
        ? cv.Mat.fromList(h, w, cv.MatType.CV_8UC1, blueChroma)
        : null;
    // Jaune ⇔ peu de bleu : la « chaleur » du papier est l'inverse de Cb.
    final warmth = cb == null ? null : cv.bitwiseNOT(cb);
    try {
      return _detectIn(gray, warmth: warmth);
    } finally {
      gray.dispose();
      cb?.dispose();
      warmth?.dispose();
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

  /// Passes successives, de la plus sûre à la plus permissive : bords francs (fond sombre,
  /// seuils d'Otsu), bords faibles (fond clair : contraste égalisé, seuils bas), puis couleur
  /// (canal jaune-bleu : ticket crème sur feuille blanche). Un contour qui touche les bords de
  /// l'image est probablement la surface sous le document : il ne sert qu'en dernier recours.
  Quad? _detectIn(cv.Mat gray, {cv.Mat? warmth}) {
    final blurred = cv.gaussianBlur(gray, (5, 5), 0);
    try {
      final passes = <(cv.Mat Function(), bool)>[
        (() => _strongEdges(blurred), true),
        (() => _weakEdges(blurred), true),
        if (warmth != null) (() => _colourRegion(warmth), false),
      ];
      Quad? fallback;
      for (final (pass, mayFallBack) in passes) {
        for (final quad in _quads(pass(), gray)) {
          if (!_touchesBorder(quad)) return quad;
          if (mayFallBack) fallback ??= quad;
        }
      }
      return fallback;
    } finally {
      blurred.dispose();
    }
  }

  static bool _touchesBorder(Quad q) =>
      q.corners
          .where(
            (c) =>
                c.x < _borderMargin ||
                c.y < _borderMargin ||
                c.x > 1 - _borderMargin ||
                c.y > 1 - _borderMargin,
          )
          .length >=
      2;

  /// Zone plus « chaude » que son voisinage (papier thermique crème sur feuille blanche), par seuil
  /// adaptatif sur le canal jaune-bleu étiré : robuste à un éclairage inégal. Rien si la teinte
  /// varie trop peu dans l'image (pas de papier coloré, seulement du bruit).
  cv.Mat _colourRegion(cv.Mat warmth) {
    final blurred = cv.gaussianBlur(warmth, (5, 5), 0);
    final (min, max, _, _) = cv.minMaxLoc(blurred);
    if (max - min < _minWarmthRange) {
      blurred.dispose();
      return cv.Mat.zeros(warmth.rows, warmth.cols, cv.MatType.CV_8UC1);
    }
    final stretched = cv.normalize(
      blurred,
      cv.Mat.empty(),
      alpha: 0,
      beta: 255,
      normType: cv.NORM_MINMAX,
    );
    final block = (math.min(warmth.rows, warmth.cols) ~/ 6) | 1;
    final mask = cv.adaptiveThreshold(
      stretched,
      255,
      cv.ADAPTIVE_THRESH_MEAN_C,
      cv.THRESH_BINARY,
      block,
      -2,
    );
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (9, 9));
    final opened = cv.morphologyEx(mask, cv.MORPH_OPEN, kernel);
    try {
      return cv.morphologyEx(opened, cv.MORPH_CLOSE, kernel);
    } finally {
      for (final m in [blurred, stretched, mask, kernel, opened]) {
        m.dispose();
      }
    }
  }

  cv.Mat _strongEdges(cv.Mat blurred) {
    final (otsu, binary) = cv.threshold(
      blurred,
      0,
      255,
      cv.THRESH_BINARY | cv.THRESH_OTSU,
    );
    final edges = cv.canny(blurred, otsu * 0.5, otsu);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (3, 3));
    try {
      return cv.dilate(edges, kernel);
    } finally {
      for (final m in [binary, edges, kernel]) {
        m.dispose();
      }
    }
  }

  cv.Mat _weakEdges(cv.Mat blurred) {
    final clahe = cv.CLAHE.create(_weakClaheClip, (8, 8));
    final equalized = clahe.apply(blurred);
    final edges = cv.canny(equalized, _weakCannyLow, _weakCannyHigh);
    final kernel = cv.getStructuringElement(cv.MORPH_RECT, (5, 5));
    final closed = cv.morphologyEx(edges, cv.MORPH_CLOSE, kernel);
    try {
      return cv.dilate(closed, kernel);
    } finally {
      clahe.dispose();
      for (final m in [equalized, edges, kernel, closed]) {
        m.dispose();
      }
    }
  }

  /// Contours à 4 coins, convexes, d'une aire plausible, qui remplissent leur quadrilatère (un
  /// objet arrondi ramené de force à 4 points est rejeté), du plus sûr au moins sûr : toutes les
  /// formes à la tolérance stricte, puis tolérances assouplies (bords irréguliers, coins arrondis).
  ///
  /// Les contours intérieurs comptent aussi : quand le bord d'un ticket touche celui d'un autre
  /// objet (clavier), le bord extérieur fusionne mais le bord intérieur reste un quadrilatère.
  List<Quad> _quads(cv.Mat edges, cv.Mat gray) {
    final (contours, hierarchy) = cv.findContours(
      edges,
      cv.RETR_LIST,
      cv.CHAIN_APPROX_SIMPLE,
    );
    final found = <Quad>[];
    try {
      final imageArea = (gray.rows * gray.cols).toDouble();
      final candidates =
          (contours.toList()..sort(
                (a, b) => cv.contourArea(b).compareTo(cv.contourArea(a)),
              ))
              .take(5)
              .toList();
      for (final tolerance in _approxTolerances) {
        for (final contour in candidates) {
          final approx = cv.approxPolyDP(
            contour,
            tolerance * cv.arcLength(contour, true),
            true,
          );
          try {
            if (approx.length != 4 || !cv.isContourConvex(approx)) continue;
            final quadArea = cv.contourArea(approx);
            final ratio = quadArea / imageArea;
            if (ratio < _minAreaRatio || ratio > _maxAreaRatio) continue;
            final fill = cv.contourArea(contour) / quadArea;
            if ((fill - 1).abs() > _maxFillGap) continue;
            found.add(
              Quad.fromUnordered([
                for (final p in approx.toList())
                  Corner(p.x / gray.cols, p.y / gray.rows),
              ]),
            );
          } finally {
            approx.dispose();
          }
        }
      }
      return found;
    } finally {
      edges.dispose();
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
  Uint8List? blueChroma,
}) => Isolate.run(
  () => const DocumentScanner().detectInLuma(
    luma,
    width: width,
    height: height,
    bytesPerRow: width,
    blueChroma: blueChroma,
  ),
);

/// Échantillonne le plan U (Cb) d'un flux YUV 4:2:0 (demi-résolution ; [pixelStride] 2 quand U et V
/// sont entrelacés, comme en NV12 sur iOS) à la taille [width] x [height] de la luminance réduite.
Uint8List sampleChroma(
  Uint8List plane, {
  required int lumaWidth,
  required int lumaHeight,
  required int bytesPerRow,
  required int pixelStride,
  required int width,
  required int height,
}) {
  final out = Uint8List(width * height);
  for (var y = 0; y < height; y++) {
    final row = (y * lumaHeight ~/ height) ~/ 2 * bytesPerRow;
    for (var x = 0; x < width; x++) {
      out[y * width + x] =
          plane[row + (x * lumaWidth ~/ width) ~/ 2 * pixelStride];
    }
  }
  return out;
}

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
