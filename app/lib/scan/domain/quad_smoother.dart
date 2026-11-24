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

  /// Contour à afficher après la détection [detected] (nul si rien trouvé sur cette image).
  Quad? update(Quad? detected, DateTime now) {
    final shown = _shown;
    final lost = _seen == null || now.difference(_seen!) > dropout;
    if (detected == null) {
      if (lost) _shown = null;
      return _shown;
    }
    if (shown == null) {
      _shown = detected;
    } else if (detected.maxShift(shown) <= jump) {
      _shown = shown.lerpTo(detected, follow);
    } else if (lost) {
      _shown = detected;
    } else {
      return shown;
    }
    _seen = now;
    return _shown;
  }
}
