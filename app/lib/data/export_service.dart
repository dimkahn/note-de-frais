import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Frontière vers le menu de partage du système (e-mail, messagerie, « Enregistrer dans Fichiers »…).
abstract interface class FileSharer {
  Future<void> share(List<File> files, {required String subject});
}

/// Export d'un justificatif ou d'un document : un PDF de toutes les pages, ou les photos recadrées
/// (format d'origine conservé).
final class ExportService {
  ExportService({required this._sharer, required this._tempDir});

  static const _maxNameLength = 100;

  final FileSharer _sharer;
  final Directory _tempDir;

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

  Future<void> sharePdf(String title, List<String> imagePaths) async {
    final file = File(
      p.join((await _exportDir()).path, '${_fileName(title)}.pdf'),
    );
    await file.writeAsBytes(await buildPdf(imagePaths), flush: true);
    await _sharer.share([file], subject: title);
  }

  /// Copies des images recadrées, nommées d'après le titre (les fichiers de l'app restent intacts).
  Future<void> sharePhotos(String title, List<String> imagePaths) async {
    final dir = await _exportDir();
    final name = _fileName(title);
    final files = <File>[];
    for (final (i, path) in imagePaths.indexed) {
      final suffix = imagePaths.length > 1 ? ' - page ${i + 1}' : '';
      final ext = p.extension(path).toLowerCase();
      files.add(
        await File(
          path,
        ).copy(p.join(dir.path, '$name$suffix${ext.isEmpty ? '.jpg' : ext}')),
      );
    }
    await _sharer.share(files, subject: title);
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
