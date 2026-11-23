import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/export_service.dart';

enum _ExportAction {
  sharePdf(
    Icons.picture_as_pdf_outlined,
    'Partager le PDF',
    'Toutes les pages dans un fichier',
  ),
  sharePhotos(
    Icons.image_outlined,
    'Partager les photos',
    'Une image par page',
  ),
  savePdf(
    Icons.download_outlined,
    'PDF dans Téléchargements',
    'Sur l\'appareil, sans partager',
  ),
  savePhotos(
    Icons.download_outlined,
    'Photos dans Téléchargements',
    'Sur l\'appareil, sans partager',
  );

  const _ExportAction(this.icon, this.label, this.detail);

  final IconData icon;
  final String label;
  final String detail;
}

/// Menu « Exporter » : PDF ou photos recadrées, par le menu de partage ou directement dans
/// Téléchargements.
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
  Widget build(BuildContext context) => PopupMenuButton<_ExportAction>(
    tooltip: 'Exporter',
    icon: const Icon(Icons.ios_share),
    enabled: imagePaths.isNotEmpty,
    onSelected: (action) => _export(context, action),
    itemBuilder: (_) => [
      for (final action in _ExportAction.values) ...[
        if (action == _ExportAction.savePdf) const PopupMenuDivider(),
        PopupMenuItem(
          value: action,
          child: ListTile(
            leading: Icon(action.icon),
            title: Text(action.label),
            subtitle: Text(action.detail),
          ),
        ),
      ],
    ],
  );

  Future<void> _export(BuildContext context, _ExportAction action) async {
    final export = context.read<ExportService>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = switch (action) {
        _ExportAction.sharePdf => await _share(
          export.sharePdf(title, imagePaths),
        ),
        _ExportAction.sharePhotos => await _share(
          export.sharePhotos(title, imagePaths),
        ),
        _ExportAction.savePdf => await export.savePdf(title, imagePaths),
        _ExportAction.savePhotos => await export.savePhotos(title, imagePaths),
      };
      if (saved.isNotEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(_savedMessage(saved))));
      }
    } catch (e, st) {
      debugPrint('Export impossible : $e\n$st');
      messenger.showSnackBar(
        const SnackBar(content: Text('Export impossible')),
      );
    }
  }

  static Future<List<File>> _share(Future<void> sharing) async {
    await sharing;
    return const [];
  }

  static String _savedMessage(List<File> saved) => saved.length == 1
      ? 'Enregistré dans Téléchargements : ${saved.single.uri.pathSegments.last}'
      : '${saved.length} fichiers enregistrés dans Téléchargements';
}
