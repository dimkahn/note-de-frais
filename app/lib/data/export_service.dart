import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Frontière vers le menu de partage du système (e-mail, messagerie, « Enregistrer dans Fichiers »…).
abstract interface class FileSharer {
  Future<void> share(List<File> files, {required String subject});
}

/// Note de frais mise en forme (textes déjà formatés par l'interface).
final class ExpenseReport {
  const ExpenseReport({
    required this.title,
    required this.totals,
    required this.lines,
  });

  final String title;

  /// Totaux par devise, ex. « 25,50 € · 12,00 CHF ».
  final String totals;
  final List<ReportLine> lines;

  List<String> get imagePaths => [
    for (final l in lines)
      if (l.imagePath != null) l.imagePath!,
  ];
}

final class ReportLine {
  const ReportLine({
    required this.date,
    required this.merchant,
    required this.category,
    required this.total,
    required this.vat,
    required this.caption,
    required this.imagePath,
  });

  final String date;
  final String merchant;
  final String category;
  final String total;
  final String vat;

  /// Légende de la page du justificatif.
  final String caption;
  final String? imagePath;
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

  /// Synthèse (tableau des dépenses, totaux) puis une page par justificatif, légendée.
  Future<Uint8List> buildReport(ExpenseReport report) async {
    final theme = await _pdfTheme();
    final ink = PdfColor.fromInt(0xFF2747D8);
    final pdf = pw.Document(title: report.title, theme: theme);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => [
          pw.Text(
            report.title,
            style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '${report.lines.length} justificatif${report.lines.length > 1 ? 's' : ''}',
          ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['Date', 'Commerçant', 'Type', 'TTC', 'TVA'],
            data: [
              for (final l in report.lines)
                [l.date, l.merchant, l.category, l.total, l.vat],
            ],
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: pw.BoxDecoration(color: ink),
            cellAlignments: {
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
            },
            oddRowDecoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF1F3FB),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Total : ${report.totals}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    for (final line in report.lines) {
      final path = line.imagePath;
      if (path == null || !File(path).existsSync()) continue;
      final image = pw.MemoryImage(await File(path).readAsBytes());
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                line.caption,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 8),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return pdf.save();
  }

  Future<void> shareReport(ExpenseReport report) async => _sharer.share([
    await _write('${_fileName(report.title)}.pdf', await buildReport(report)),
  ], subject: report.title);

  Future<List<File>> saveReport(ExpenseReport report) async => _saveAll([
    await _write('${_fileName(report.title)}.pdf', await buildReport(report)),
  ]);

  /// Police embarquée (Noto Sans) : accents, €, tirets — absents des polices PDF standard.
  static Future<pw.ThemeData> _pdfTheme() async => pw.ThemeData.withFont(
    base: pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    ),
    bold: pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf')),
  );

  Future<File> _write(String name, Uint8List bytes) async =>
      File(p.join((await _exportDir()).path, name))
          .writeAsBytes(bytes, flush: true);

  Future<void> sharePdf(String title, List<String> imagePaths) async =>
      _sharer.share([await _pdfFile(title, imagePaths)], subject: title);

  Future<void> sharePhotos(String title, List<String> imagePaths) async =>
      _sharer.share(await _photoFiles(title, imagePaths), subject: title);

  /// Enregistre directement dans Téléchargements ; renvoie le fichier créé.
  Future<List<File>> savePdf(String title, List<String> imagePaths) async =>
      _saveAll([await _pdfFile(title, imagePaths)]);

  Future<List<File>> savePhotos(String title, List<String> imagePaths) async =>
      _saveAll(await _photoFiles(title, imagePaths));

  Future<File> _pdfFile(String title, List<String> imagePaths) async =>
      _write('${_fileName(title)}.pdf', await buildPdf(imagePaths));

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
