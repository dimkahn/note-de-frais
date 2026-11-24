import 'dart:math' as math;

/// Point normalisé (0..1) dans le repère de l'image.
final class Corner {
  const Corner(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(Corner o) =>
      math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  Corner clamped() => Corner(x.clamp(0.0, 1.0), y.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) =>
      other is Corner && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => '($x, $y)';
}

/// Contour du document : 4 coins normalisés, ordre haut-gauche, haut-droit, bas-droit, bas-gauche,
/// dans le repère de l'image orientée. Même format texte que `server/.../imaging/Quad.java`.
final class Quad {
  const Quad(this.topLeft, this.topRight, this.bottomRight, this.bottomLeft);

  /// Rectangle en retrait de [margin] sur chaque bord (cadre par défaut).
  factory Quad.inset(double margin) => Quad(
    Corner(margin, margin),
    Corner(1 - margin, margin),
    Corner(1 - margin, 1 - margin),
    Corner(margin, 1 - margin),
  );

  /// Remet 4 points quelconques dans l'ordre attendu (même règle que le serveur).
  factory Quad.fromUnordered(List<Corner> pts) {
    assert(pts.length == 4);
    Corner by(double Function(Corner) key, {required bool max}) =>
        pts.reduce((a, b) => (key(a) > key(b)) == max ? a : b);
    return Quad(
      by((p) => p.x + p.y, max: false),
      by((p) => p.y - p.x, max: false),
      by((p) => p.x + p.y, max: true),
      by((p) => p.y - p.x, max: true),
    );
  }

  factory Quad.parse(String text) {
    final parts = text.split(',');
    if (parts.length != 8) {
      throw FormatException('8 coordonnées attendues', text);
    }
    final v = parts.map((p) => double.parse(p.trim())).toList();
    return Quad(
      Corner(v[0], v[1]),
      Corner(v[2], v[3]),
      Corner(v[4], v[5]),
      Corner(v[6], v[7]),
    );
  }

  final Corner topLeft;
  final Corner topRight;
  final Corner bottomRight;
  final Corner bottomLeft;

  List<Corner> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  String format() => corners
      .expand((c) => [c.x, c.y])
      .map(
        (d) => d
            .toStringAsFixed(5)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), ''),
      )
      .join(',');

  bool get isConvex {
    final pts = corners;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4], c = pts[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      if (cross.abs() < 1e-6) return false;
      final s = cross > 0 ? 1 : -1;
      if (sign != 0 && s != sign) return false;
      sign = s;
    }
    return true;
  }

  /// Aire (formule du lacet), en fraction de l'image.
  double get area {
    final pts = corners;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = pts[i], b = pts[(i + 1) % 4];
      sum += a.x * b.y - b.x * a.y;
    }
    return sum.abs() / 2;
  }

  /// Plus grand déplacement d'un coin entre deux contours.
  double maxShift(Quad other) {
    final a = corners, b = other.corners;
    return [for (var i = 0; i < 4; i++) a[i].distanceTo(b[i])].reduce(math.max);
  }

  /// Contour à la fraction [t] du chemin vers [other], coin par coin.
  Quad lerpTo(Quad other, double t) {
    final a = corners, b = other.corners;
    Corner at(int i) =>
        Corner(a[i].x + (b[i].x - a[i].x) * t, a[i].y + (b[i].y - a[i].y) * t);
    return Quad(at(0), at(1), at(2), at(3));
  }

  Quad withCorner(int index, Corner c) {
    final pts = corners..[index] = c;
    return Quad(pts[0], pts[1], pts[2], pts[3]);
  }

  /// Déplacement d'un coin par l'utilisateur : borné à l'image, refusé s'il rendrait le contour non convexe.
  Quad moveCorner(int index, Corner target) {
    final moved = withCorner(index, target.clamped());
    return moved.isConvex ? moved : this;
  }

  /// Passe du repère du capteur au repère affiché, pour une rotation horaire de [degrees].
  Quad rotated(int degrees) {
    Corner rotate(Corner c) => switch (degrees % 360) {
      90 => Corner(1 - c.y, c.x),
      180 => Corner(1 - c.x, 1 - c.y),
      270 => Corner(c.y, 1 - c.x),
      _ => c,
    };
    if (degrees % 360 == 0) return this;
    return Quad.fromUnordered(corners.map(rotate).toList());
  }

  @override
  bool operator ==(Object other) => other is Quad && other.format() == format();

  @override
  int get hashCode => format().hashCode;

  @override
  String toString() => 'Quad(${format()})';
}
