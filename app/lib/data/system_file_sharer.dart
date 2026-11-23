import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'export_service.dart';

/// Menu de partage du système (Android / iOS / desktop) via `share_plus`.
final class SystemFileSharer implements FileSharer {
  const SystemFileSharer();

  @override
  Future<void> share(List<File> files, {required String subject}) =>
      SharePlus.instance.share(
        ShareParams(
          files: [for (final f in files) XFile(f.path)],
          subject: subject,
          title: subject,
        ),
      );
}
