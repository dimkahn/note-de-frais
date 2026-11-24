/// Quart de tour horaire appliqué au rendu, après redressement et filtre (aligné sur `Rotation` serveur).
enum Rotation {
  none(0),
  clockwise90(90),
  clockwise180(180),
  clockwise270(270);

  const Rotation(this.degrees);

  final int degrees;

  /// Lecture tolérante (serveur, base locale) : une valeur absente ou inconnue ne pivote pas.
  static Rotation fromDegrees(Object? degrees) =>
      values.firstWhere((r) => r.degrees == degrees, orElse: () => none);

  /// Quart de tour horaire suivant (bouton « Pivoter »).
  Rotation next() => values[(index + 1) % values.length];
}
