import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class OriginalExistsException implements Exception {
  OriginalExistsException(this.expenseId);

  final String expenseId;

  @override
  String toString() => 'L\'original de la dépense $expenseId existe déjà';
}

/// Stockage local des justificatifs : `<racine>/<id>/original.<ext>` (écriture unique)
/// et `<racine>/<id>/processed.jpg` (remplaçable).
final class FileStore {
  FileStore(this.root);

  final Directory root;

  /// Copie la photo prise/choisie ; la source n'est ni déplacée ni modifiée.
  Future<File> saveOriginal(String expenseId, String sourcePath) async {
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    return saveOriginalBytes(
      expenseId,
      await File(sourcePath).readAsBytes(),
      ext,
    );
  }

  Future<File> saveOriginalBytes(
    String expenseId,
    List<int> bytes,
    String extension,
  ) async {
    final target = originalFile(expenseId, extension);
    if (await target.exists()) throw OriginalExistsException(expenseId);
    await target.parent.create(recursive: true);
    // Écriture dans un fichier temporaire puis renommage : jamais d'original partiel.
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    return tmp.rename(target.path);
  }

  Future<File> saveProcessed(String expenseId, List<int> jpeg) async {
    final target = File(p.join(_dir(expenseId).path, 'processed.jpg'));
    await target.parent.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(jpeg, flush: true);
    return tmp.rename(target.path);
  }

  /// Écrit un nouveau rendu sous un nom inédit : le cache d'images, indexé par chemin, ne peut pas
  /// montrer l'ancien.
  Future<File> saveProcessedVersion(String id, List<int> jpeg) async {
    final dir = _dir(id);
    final target = File(p.join(dir.path, 'processed-${const Uuid().v4()}.jpg'));
    await dir.create(recursive: true);
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(jpeg, flush: true);
    return tmp.rename(target.path);
  }

  /// Efface un ancien rendu ; ne fait rien si [path] n'est pas un rendu du dossier [id] :
  /// un original n'est jamais effacé.
  Future<void> deleteProcessed(String id, String path) async {
    if (!p.equals(p.dirname(path), _dir(id).path) ||
        !p.basename(path).startsWith('processed')) {
      return;
    }
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  File originalFile(String expenseId, String extension) {
    final ext = extension.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return File(
      p.join(_dir(expenseId).path, 'original.${ext.isEmpty ? 'jpg' : ext}'),
    );
  }

  Directory _dir(String expenseId) {
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(expenseId)) {
      throw ArgumentError.value(expenseId, 'expenseId', 'identifiant invalide');
    }
    return Directory(p.join(root.path, expenseId));
  }
}
