import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/export_service.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Retient ce qui aurait été partagé.
final class _FakeSharer implements FileSharer {
  final shared = <File>[];
  String? subject;

  @override
  Future<void> share(List<File> files, {required String subject}) async {
    shared.addAll(files);
    this.subject = subject;
  }
}

final class _FolderInTemp implements DownloadsFolder {
  _FolderInTemp(this.dir);

  final Directory dir;

  @override
  Future<Directory> locate() => dir.create(recursive: true);
}

void main() {
  // Les polices du PDF sont lues dans les assets de l'app.
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Directory downloads;
  late _FakeSharer sharer;
  late ExportService export;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_export');
    downloads = Directory('${dir.path}/Download');
    sharer = _FakeSharer();
    export = ExportService(
      sharer: sharer,
      tempDir: dir,
      downloads: _FolderInTemp(downloads),
    );
  });

  tearDown(() => dir.delete(recursive: true));

  String jpeg(String name, int w, int h) {
    final img = cv.Mat.fromScalar(
      h,
      w,
      cv.MatType.CV_8UC3,
      cv.Scalar(200, 220, 240),
    );
    final (_, bytes) = cv.imencode('.jpg', img);
    img.dispose();
    return (File('${dir.path}/$name.jpg')..writeAsBytesSync(bytes)).path;
  }

  int pageCount(List<int> pdf) =>
      RegExp(r'/Type\s*/Page(?!s)').allMatches(latin1.decode(pdf)).length;

  test('construit un PDF d\'une page par image', () async {
    final pdf = await export.buildPdf([
      jpeg('a', 600, 800),
      jpeg('b', 800, 600),
    ]);

    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pageCount(pdf), 2);
  });

  test('partage le PDF sous le titre du document', () async {
    await export.sharePdf('Contrat de bail', [jpeg('a', 600, 800)]);

    final file = sharer.shared.single;
    expect(file.uri.pathSegments.last, 'Contrat de bail.pdf');
    expect(latin1.decode(file.readAsBytesSync().sublist(0, 5)), '%PDF-');
    expect(sharer.subject, 'Contrat de bail');
  });

  test('partage les photos recadrées, numérotées par page', () async {
    final a = jpeg('a', 600, 800), b = jpeg('b', 600, 800);

    await export.sharePhotos('Bail', [a, b]);

    expect(sharer.shared.map((f) => f.uri.pathSegments.last), [
      'Bail - page 1.jpg',
      'Bail - page 2.jpg',
    ]);
    expect(sharer.shared.first.readAsBytesSync(), File(a).readAsBytesSync());
  });

  test('une seule photo n\'est pas numérotée', () async {
    await export.sharePhotos('Ticket', [jpeg('a', 600, 800)]);

    expect(sharer.shared.single.uri.pathSegments.last, 'Ticket.jpg');
  });

  test('un titre est rendu sûr comme nom de fichier', () async {
    await export.sharePdf('Bail 2026/11: "final"', [jpeg('a', 60, 80)]);

    expect(
      sharer.shared.single.uri.pathSegments.last,
      'Bail 2026-11- -final-.pdf',
    );
  });

  test(
    'garde le format d\'origine d\'une image qui n\'est pas un JPEG',
    () async {
      final png = File('${dir.path}/scan.png')..writeAsBytesSync([1, 2, 3]);

      await export.sharePhotos('Ticket', [png.path]);

      expect(sharer.shared.single.uri.pathSegments.last, 'Ticket.png');
    },
  );

  test('ne laisse pas traîner les exports précédents', () async {
    await export.sharePdf('Ancien', [jpeg('a', 60, 80)]);
    final previous = sharer.shared.single;

    await export.sharePdf('Nouveau', [jpeg('b', 60, 80)]);

    expect(previous.existsSync(), isFalse);
  });

  group('Téléchargements', () {
    test('enregistre le PDF directement, sans menu de partage', () async {
      final saved = await export.savePdf('Bail', [jpeg('a', 60, 80)]);

      expect(saved.single.path, '${downloads.path}/Bail.pdf');
      expect(
        latin1.decode(saved.single.readAsBytesSync().sublist(0, 5)),
        '%PDF-',
      );
      expect(sharer.shared, isEmpty);
    });

    test('n\'écrase jamais un fichier déjà présent', () async {
      await export.savePdf('Bail', [jpeg('a', 60, 80)]);

      final second = await export.savePdf('Bail', [jpeg('b', 60, 80)]);

      expect(second.single.uri.pathSegments.last, 'Bail (2).pdf');
      expect(File('${downloads.path}/Bail.pdf').existsSync(), isTrue);
    });

    test('enregistre les photos numérotées', () async {
      final saved = await export.savePhotos('Bail', [
        jpeg('a', 60, 80),
        jpeg('b', 60, 80),
      ]);

      expect(saved.map((f) => f.uri.pathSegments.last), [
        'Bail - page 1.jpg',
        'Bail - page 2.jpg',
      ]);
      expect(saved.every((f) => f.parent.path == downloads.path), isTrue);
    });
  });

  test(
    'la note de frais : une synthèse puis une page par justificatif',
    () async {
      final report = ExpenseReport(
        title: 'Note de frais — mars 2026',
        totals: '25,50 €',
        lines: [
          ReportLine(
            date: '2 mars 2026',
            merchant: 'Café de la Gare',
            category: 'Restaurant',
            total: '5,50 €',
            vat: '—',
            caption: '2 mars 2026 · Café de la Gare · 5,50 €',
            imagePath: jpeg('a', 600, 800),
          ),
          ReportLine(
            date: '10 mars 2026',
            merchant: 'Hôtel',
            category: 'Hôtel',
            total: '20,00 €',
            vat: '1,82 €',
            caption: '10 mars 2026 · Hôtel · 20,00 €',
            imagePath: jpeg('b', 800, 600),
          ),
          const ReportLine(
            date: '11 mars 2026',
            merchant: 'Sans photo',
            category: 'Autre',
            total: '0,00 €',
            vat: '—',
            caption: '',
            imagePath: null,
          ),
        ],
      );

      final pdf = await export.buildReport(report);

      expect(pageCount(pdf), 3);
    },
  );
}
