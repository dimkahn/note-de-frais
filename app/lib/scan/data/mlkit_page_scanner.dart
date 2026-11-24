import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart'
    as mlkit;

import '../domain/page_scanner.dart';

/// Scanner de documents ML Kit (services Google Play, Android) : prise de vue, détection et
/// recadrage par le modèle de Google, retouche de base (recadrer, pivoter) ; nos filtres
/// s'appliquent ensuite dans la revue.
final class MlKitPageScanner implements PageScanner {
  const MlKitPageScanner();

  /// Limite technique quand aucune n'est demandée (ML Kit en exige une).
  static const maxPages = 100;

  /// Message du plugin quand l'utilisateur quitte le scanner.
  static const _cancelled = 'Operation cancelled';

  @override
  Future<List<String>?> scan({int? pageLimit}) async {
    final scanner = mlkit.DocumentScanner(
      options: mlkit.DocumentScannerOptions(
        documentFormats: const {mlkit.DocumentFormat.jpeg},
        mode: mlkit.ScannerMode.base,
        pageLimit: pageLimit ?? maxPages,
        isGalleryImport: true,
      ),
    );
    try {
      final result = await scanner.scanDocument();
      return result.images ?? const [];
    } on PlatformException catch (e) {
      if (e.message == _cancelled) return null;
      throw PageScannerUnavailable(e.message ?? e.code);
    } on MissingPluginException catch (e) {
      throw PageScannerUnavailable(e.message ?? 'plugin absent');
    } finally {
      try {
        await scanner.close();
      } on Object catch (e) {
        debugPrint('Fermeture du scanner ML Kit : $e');
      }
    }
  }
}
