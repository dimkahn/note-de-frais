import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Frontière vers le menu de partage du système (e-mail, messagerie, « Enregistrer dans Fichiers »…).
abstract interface class FileSharer {
  Future<void> share(List<File> files, {required String subject});
}

/// Frontière vers le dossier Téléchargements de l'appareil (sur iOS : dossier de l'app visible
/// dans l'application Fichiers).
abstract interface class DownloadsFolder {
  Future<Directory> locate();
}

/// Export d'un justificatif ou d'un document : un PDF de toutes les pages, ou les photos recadrées
/// (format d'origine conservé).
final class ExportService {
  ExportService({
    required this._sharer,
    required this._tempDir,
    required this._downloads,
  });

  static const _maxNameLength = 100;

  final FileSharer _sharer;
  final Directory _tempDir;
  final DownloadsFolder _downloads;

  /// Une page A4 par image (paysage si l'image l'est), image entière sans marge.
  Future<Uint8List> buildPdf(List<String> imagePaths) async {
    final pdf = pw.Document();
    for (final path in imagePaths) {
      final image = pw.MemoryImage(await File(path).readAsBytes());
      final landscape = (image.width ?? 0) > (image.height ?? 0);
      pdf.addPage(
        pw.Page(
          pageFormat: landscape ? PdfPageFormat.a4.landscape : PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (_) =>
              pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    return pdf.save();
  }

  Future<void> sharePdf(String title, List<String> imagePaths) async =>
      _sharer.share([await _pdfFile(title, imagePaths)], subject: title);

  Future<void> sharePhotos(String title, List<String> imagePaths) async =>
      _sharer.share(await _photoFiles(title, imagePaths), subject: title);

  /// Enregistre directement dans Téléchargements ; renvoie le fichier créé.
  Future<List<File>> savePdf(String title, List<String> imagePaths) async =>
      _saveAll([await _pdfFile(title, imagePaths)]);

  Future<List<File>> savePhotos(String title, List<String> imagePaths) async =>
      _saveAll(await _photoFiles(title, imagePaths));

  Future<File> _pdfFile(String title, List<String> imagePaths) async {
    final file = File(
      p.join((await _exportDir()).path, '${_fileName(title)}.pdf'),
    );
    return file.writeAsBytes(await buildPdf(imagePaths), flush: true);
  }

  /// Copies des images recadrées, nommées d'après le titre, au format d'origine (les fichiers de
  /// l'app restent intacts).
  Future<List<File>> _photoFiles(String title, List<String> imagePaths) async {
    final dir = await _exportDir();
    final name = _fileName(title);
    return [
      for (final (i, path) in imagePaths.indexed)
        await File(path).copy(
          p.join(
            dir.path,
            '$name${imagePaths.length > 1 ? ' - page ${i + 1}' : ''}'
            '${p.extension(path).isEmpty ? '.jpg' : p.extension(path).toLowerCase()}',
          ),
        ),
    ];
  }

  /// Copie dans Téléchargements sans jamais écraser : « Bail.pdf », puis « Bail (2).pdf »…
  Future<List<File>> _saveAll(List<File> files) async {
    final target = await _downloads.locate();
    return [for (final file in files) await file.copy(_freeName(target, file))];
  }

  static String _freeName(Directory dir, File file) {
    final base = p.basenameWithoutExtension(file.path);
    final ext = p.extension(file.path);
    var candidate = p.join(dir.path, '$base$ext');
    for (var n = 2; File(candidate).existsSync(); n++) {
      candidate = p.join(dir.path, '$base ($n)$ext');
    }
    return candidate;
  }

  /// Dossier d'export vidé à chaque export : aucune copie de justificatif ne s'accumule.
  Future<Directory> _exportDir() async {
    final dir = Directory(p.join(_tempDir.path, 'export'));
    if (await dir.exists()) await dir.delete(recursive: true);
    return dir.create(recursive: true);
  }

  static String _fileName(String title) {
    var safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
    if (safe.length > _maxNameLength) safe = safe.substring(0, _maxNameLength);
    return safe.isEmpty ? 'document' : safe;
  }
}
