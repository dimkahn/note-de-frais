import 'dart:io';

import 'package:note_de_frais/export/data/export_service.dart';

/// Dossier Téléchargements de test, dans un répertoire temporaire.
final class TempDownloads implements DownloadsFolder {
  TempDownloads(this.dir);

  final Directory dir;

  @override
  Future<Directory> locate() => dir.create(recursive: true);
}
