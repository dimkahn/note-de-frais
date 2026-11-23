import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'export_service.dart';

/// Téléchargements selon la plateforme :
/// - Android : dossier public `Download` (création de fichiers autorisée sans permission depuis
///   Android 10 ; `requestLegacyExternalStorage` couvre Android 10) ;
/// - iOS : dossier Documents de l'app, visible dans Fichiers › Sur mon iPhone › Note de frais ;
/// - desktop : dossier Téléchargements de l'utilisateur.
final class PlatformDownloadsFolder implements DownloadsFolder {
  const PlatformDownloadsFolder();

  @override
  Future<Directory> locate() async {
    if (Platform.isAndroid) {
      return Directory('/storage/emulated/0/Download').create(recursive: true);
    }
    if (Platform.isIOS) return getApplicationDocumentsDirectory();
    return await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
  }
}
