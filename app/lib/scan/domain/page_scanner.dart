/// Scanner de documents du système (ML Kit sur Android) : prise de vue, détection et recadrage.
abstract interface class PageScanner {
  /// Chemins des pages scannées, déjà recadrées ; `null` si l'utilisateur abandonne.
  /// [pageLimit] : pages au plus (`null` : sans limite).
  /// Lève [PageScannerUnavailable] si le scanner ne peut pas démarrer.
  Future<List<String>?> scan({int? pageLimit});
}

/// Le scanner système ne peut pas servir (pas de services Google Play, module absent…).
final class PageScannerUnavailable implements Exception {
  const PageScannerUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'Scanner indisponible : $reason';
}
