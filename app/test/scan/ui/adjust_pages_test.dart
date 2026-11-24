import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/document/data/document_repository.dart';
import 'package:note_de_frais/shared/data/file_store.dart';
import 'package:note_de_frais/shared/data/local_store.dart';
import 'package:note_de_frais/document/domain/document.dart';
import 'package:note_de_frais/expense/domain/expense.dart';
import 'package:note_de_frais/scan/domain/quad.dart';
import 'package:note_de_frais/scan/domain/rotation.dart';
import 'package:note_de_frais/scan/ui/adjust_screen.dart';
import 'package:note_de_frais/scan/ui/capture.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/signed_out_account.dart';

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late LocalStore store;
  late DocumentRepository repo;
  late ScannedDocument doc;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ndf_adjust');
    store = await LocalStore.open(
      inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repo = DocumentRepository(
      store: store,
      files: FileStore(dir),
      httpClient: noServer,
      account: await signedOutAccount(store),
    );
    await repo.load();
    doc = await repo.create([
      for (final b in [1, 2, 3])
        PageCapture(
          photoPath: (File(
            '${dir.path}/photo-$b.jpg',
          )..writeAsBytesSync([b])).path,
          corners: Quad.inset(0.1),
          filter: ImageFilter.enhance,
          processedJpeg: [b],
        ),
    ]);
  });

  tearDown(() async {
    repo.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });

  PageAdjustment validated(ScannedPage page, int byte) => AdjustedPage(
    ScanResult(
      photoPath: page.originalPath,
      quad: Quad.inset(0.2),
      filter: ImageFilter.scanBw,
      processedJpeg: Uint8List.fromList([byte]),
    ),
  );

  List<int> rendered(int index) =>
      File(repo.byId(doc.id)!.pages[index].processedPath).readAsBytesSync();

  test('une page réajustée et pivotée garde sa rotation', () async {
    await adjustDocumentPages(repo, doc.id, (page, title) async {
      if (page.id != doc.pages.first.id) return const StopAdjusting();
      return AdjustedPage(
        ScanResult(
          photoPath: page.originalPath,
          quad: Quad.inset(0.2),
          filter: ImageFilter.none,
          rotation: Rotation.clockwise90,
          processedJpeg: Uint8List.fromList([4]),
        ),
      );
    });

    expect(repo.byId(doc.id)!.pages.first.rotation, Rotation.clockwise90);
  });

  test('propose chaque page à partir de son original, dans l\'ordre', () async {
    final asked = <(String, String)>[];

    await adjustDocumentPages(repo, doc.id, (page, title) async {
      asked.add((page.originalPath, title));
      return const SkippedPage();
    });

    expect(asked, [
      (doc.pages[0].originalPath, 'Page 1 sur 3'),
      (doc.pages[1].originalPath, 'Page 2 sur 3'),
      (doc.pages[2].originalPath, 'Page 3 sur 3'),
    ]);
  });

  test('enregistre les pages validées et laisse les pages passées', () async {
    await adjustDocumentPages(
      repo,
      doc.id,
      (page, _) async =>
          page.id == doc.pages[1].id ? const SkippedPage() : validated(page, 9),
    );

    expect(
      [rendered(0), rendered(1), rendered(2)],
      [
        [9],
        [2],
        [9],
      ],
    );
    expect(repo.byId(doc.id)!.pages[0].filter, ImageFilter.scanBw);
  });

  test('s\'arrête à la demande en gardant les pages déjà validées', () async {
    var asked = 0;

    await adjustDocumentPages(repo, doc.id, (page, _) async {
      asked++;
      return asked == 1 ? validated(page, 9) : const StopAdjusting();
    });

    expect(asked, 2);
    expect(
      [rendered(0), rendered(1), rendered(2)],
      [
        [9],
        [2],
        [3],
      ],
    );
  });
}
