/// Bilan d'une synchronisation (dépenses ou documents), affiché par l'onglet Compte.
final class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.errors = const [],
    this.offline = false,
    this.unauthorized = false,
    this.refusedForQuota = 0,
  });

  final int pushed;
  final int pulled;
  final List<String> errors;

  /// Le serveur était injoignable : rien n'est perdu, tout sera rejoué.
  final bool offline;

  /// La session a été refusée : il faut se reconnecter ; les changements locaux attendent.
  final bool unauthorized;

  /// Captures refusées faute d'espace en ligne : elles restent sur l'appareil, en attente d'envoi.
  final int refusedForQuota;
}
