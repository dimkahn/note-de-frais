import 'quad.dart';

/// Contour affiché pendant la visée : stable malgré les ratés et le tremblement de la détection.
final class QuadSmoother {
  QuadSmoother({
    this.follow = 0.5,
    this.jump = 0.08,
    this.dropout = const Duration(milliseconds: 400),
  });

  /// Part du chemin parcourue vers le nouveau contour à chaque image (lissage).
  final double follow;

  /// Déplacement d'un coin (fraction de l'image) au-delà duquel le contour détecté est un autre
  /// objet ou un vrai mouvement : il n'est affiché, sans lissage, que s'il persiste au-delà de
  /// [dropout] ; une image isolée qui saute sur la feuille ou la table est ignorée.
  final double jump;

  /// Durée pendant laquelle le dernier contour reste affiché quand la détection rate.
  final Duration dropout;

  Quad? _shown;
  DateTime? _seen;

  /// Dernier contour lointain vu (et quand) : un contour lointain n'est retenu que s'il se confirme.
  Quad? _far;
  DateTime? _farSeen;

  /// Contour à afficher après la détection [detected] (nul si rien trouvé sur cette image).
  Quad? update(Quad? detected, DateTime now) {
    final shown = _shown;
    final lost = _seen == null || now.difference(_seen!) > dropout;
    if (detected == null) {
      if (lost) _shown = null;
      return _shown;
    }
    final elsewhere = shown != null && detected.maxShift(shown) > jump;
    if (elsewhere) {
      // Autre objet ou vrai mouvement : ignoré tant que le contour affiché est encore vu.
      final confirmed = _confirms(detected, now);
      if (!lost) return shown;
      if (!confirmed) return _shown = null;
    }
    _shown = shown == null || elsewhere
        ? detected
        : shown.lerpTo(detected, follow);
    _far = null;
    _seen = now;
    return _shown;
  }

  /// Oublie le contour affiché (nouvelle page, autre mode) : le prochain est affiché tel quel.
  void reset() {
    _shown = null;
    _seen = null;
    _far = null;
    _farSeen = null;
  }

  /// Vrai si [detected] est proche du contour lointain vu juste avant (sans trou de plus de
  /// [dropout]) ; [detected] devient le contour lointain de référence.
  bool _confirms(Quad detected, DateTime now) {
    final far = _far, farSeen = _farSeen;
    _far = detected;
    _farSeen = now;
    return far != null &&
        now.difference(farSeen!) <= dropout &&
        detected.maxShift(far) <= jump;
  }
}
