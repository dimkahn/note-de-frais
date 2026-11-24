import '../domain/expense.dart';

enum BadgeTone { waiting, attention }

typedef StatusBadge = ({String label, BadgeTone tone});

/// Statut à signaler sur une dépense (`null` : rien à signaler).
/// Sans serveur, il n'y a ni envoi ni analyse automatique : seule la saisie manuelle compte.
StatusBadge? statusBadge(Expense e, {required bool withServer}) {
  final failed =
      e.status == ProcessingStatus.failed ||
      e.status == ProcessingStatus.extractionFailed;
  // Sans analyse IA incluse, les valeurs viennent de l'appareil, comme sans serveur.
  final analysedOnDevice =
      e.status == ProcessingStatus.notIncluded &&
      e.syncState == SyncState.synced;
  if (!withServer || analysedOnDevice) {
    if (failed) return (label: e.status.label, tone: BadgeTone.attention);
    if (e.prefilled) return (label: 'À vérifier', tone: BadgeTone.waiting);
    return needsManualEntry(e)
        ? (label: 'À compléter', tone: BadgeTone.attention)
        : null;
  }
  if (e.status == ProcessingStatus.done && e.syncState == SyncState.synced) {
    return null;
  }
  final label = switch (e.syncState) {
    SyncState.pendingUpload when withServer => 'En attente d\'envoi',
    SyncState.pendingDelete when withServer => 'Suppression en attente',
    _ => e.status.label,
  };
  return (label: label, tone: failed ? BadgeTone.attention : BadgeTone.waiting);
}

/// Sans serveur : le montant n'a pas encore été saisi à la main.
bool needsManualEntry(Expense e) => e.amountTotal == null;
