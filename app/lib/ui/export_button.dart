import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/export_service.dart';

enum _ExportFormat { pdf, photos }

/// Menu « Exporter » : PDF de toutes les pages, ou les photos recadrées, via le menu de partage.
class ExportButton extends StatelessWidget {
  const ExportButton({
    super.key,
    required this.title,
    required this.imagePaths,
  });

  final String title;

  /// Images recadrées, dans l'ordre des pages.
  final List<String> imagePaths;

  @override
  Widget build(BuildContext context) => PopupMenuButton<_ExportFormat>(
    tooltip: 'Exporter',
    icon: const Icon(Icons.ios_share),
    enabled: imagePaths.isNotEmpty,
    onSelected: (format) => _export(context, format),
    itemBuilder: (_) => const [
      PopupMenuItem(
        value: _ExportFormat.pdf,
        child: ListTile(
          leading: Icon(Icons.picture_as_pdf_outlined),
          title: Text('PDF'),
          subtitle: Text('Toutes les pages dans un fichier'),
        ),
      ),
      PopupMenuItem(
        value: _ExportFormat.photos,
        child: ListTile(
          leading: Icon(Icons.image_outlined),
          title: Text('Photos'),
          subtitle: Text('Une image par page'),
        ),
      ),
    ],
  );

  Future<void> _export(BuildContext context, _ExportFormat format) async {
    final export = context.read<ExportService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      switch (format) {
        case _ExportFormat.pdf:
          await export.sharePdf(title, imagePaths);
        case _ExportFormat.photos:
          await export.sharePhotos(title, imagePaths);
      }
    } catch (e, st) {
      debugPrint('Export impossible : $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text('Export impossible')),
      );
    }
  }
}
