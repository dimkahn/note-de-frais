import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:note_de_frais/data/file_store.dart';

void main() {
  late Directory root;
  late FileStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ndf_files');
    store = FileStore(root);
  });

  tearDown(() => root.delete(recursive: true));

  Future<File> photo(List<int> bytes, {String name = 'IMG_1.JPG'}) async =>
      File('${root.path}/$name')..writeAsBytesSync(bytes);

  test(
    'copie l\'original à l\'identique dans le dossier de la dépense',
    () async {
      final source = await photo([1, 2, 3]);

      final saved = await store.saveOriginal('abc', source.path);

      expect(saved.path, endsWith('abc/original.jpg'));
      expect(await saved.readAsBytes(), [1, 2, 3]);
      expect(
        await source.exists(),
        isTrue,
        reason: 'la photo source n\'est pas déplacée',
      );
    },
  );

  test('refuse d\'écraser un original existant', () async {
    await store.saveOriginal('abc', (await photo([1])).path);
    final other = await photo([9], name: 'autre.jpg');

    expect(
      () => store.saveOriginal('abc', other.path),
      throwsA(isA<OriginalExistsException>()),
    );
    expect(await store.originalFile('abc', 'jpg').readAsBytes(), [1]);
  });

  test('la version traitée peut être remplacée', () async {
    await store.saveProcessed('abc', [1]);

    final f = await store.saveProcessed('abc', [2]);

    expect(await f.readAsBytes(), [2]);
  });

  test('refuse un identifiant qui sortirait du dossier', () async {
    expect(() => store.saveProcessed('../x', [1]), throwsArgumentError);
  });
}
