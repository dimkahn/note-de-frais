import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/document_repository.dart';
import '../data/expense_repository.dart';
import '../domain/document.dart';
import '../domain/expense.dart';
import '../scan/adjust_screen.dart';
import '../scan/camera_screen.dart';

/// Parcours d'ajout : scanner (mobile) ou image existante (desktop), ajustement, enregistrement local.
Future<Expense?> scanReceipt(
  BuildContext context,
  ExpenseRepository repo,
) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final ScanResult? scan;
  if (mobile) {
    final scans = await Navigator.push<List<ScanResult>>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
    scan = (scans == null || scans.isEmpty) ? null : scans.first;
  } else {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      requestFullMetadata: false,
    );
    if (photo == null || !context.mounted) return null;
    scan = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => AdjustScreen(photoPath: photo.path)),
    );
  }
  if (scan == null) return null;

  final expense = await repo.captureScan(
    scan.photoPath,
    scan.quad,
    scan.filter,
    processedJpeg: scan.processedJpeg,
  );
  if (context.mounted) {
    final message = !repo.withServer
        ? 'Enregistré sur l\'appareil'
        : (repo.lastReport?.offline ?? true)
        ? 'Enregistré sur l\'appareil, envoi dès que possible'
        : 'Envoyé pour extraction';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
  return expense;
}

/// Réajuste le cadrage et/ou le filtre d'une dépense existante, à partir de son original.
Future<void> readjustReceipt(
  BuildContext context,
  ExpenseRepository repo,
  Expense e,
) async {
  final original = e.originalPath;
  if (original == null || !File(original).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Original pas encore disponible sur cet appareil'),
      ),
    );
    return;
  }
  final scan = await Navigator.push<ScanResult>(
    context,
    MaterialPageRoute(
      builder: (_) => AdjustScreen(
        photoPath: original,
        initialQuad: e.corners,
        initialFilter: e.filter,
      ),
    ),
  );
  if (scan == null) return;
  await repo.reprocess(
    e.id,
    scan.filter,
    corners: scan.quad,
    processedJpeg: scan.processedJpeg,
  );
}

/// Scan de plusieurs pages pour un document : caméra en mode multi-pages (mobile), ou plusieurs
/// images ajustées une à une (desktop). Liste vide si l'utilisateur abandonne.
Future<List<PageCapture>> scanPages(BuildContext context) async {
  final mobile = Platform.isAndroid || Platform.isIOS;
  final scans = <ScanResult>[];
  if (mobile) {
    scans.addAll(
      await Navigator.push<List<ScanResult>>(
            context,
            MaterialPageRoute(
              builder: (_) => const CameraScreen(multiPage: true),
            ),
          ) ??
          const [],
    );
  } else {
    final photos = await ImagePicker().pickMultiImage(
      requestFullMetadata: false,
    );
    for (final photo in photos) {
      if (!context.mounted) break;
      final scan = await Navigator.push<ScanResult>(
        context,
        MaterialPageRoute(builder: (_) => AdjustScreen(photoPath: photo.path)),
      );
      if (scan != null) scans.add(scan);
    }
  }
  return [
    for (final s in scans)
      PageCapture(
        photoPath: s.photoPath,
        corners: s.quad,
        filter: s.filter,
        processedJpeg: s.processedJpeg,
      ),
  ];
}

/// Choix fait sur l'écran d'ajustement d'une page de document.
sealed class PageAdjustment {
  const PageAdjustment();
}

/// Nouveau cadrage/filtre validé pour la page.
final class AdjustedPage extends PageAdjustment {
  const AdjustedPage(this.scan);

  final ScanResult scan;
}

/// Page laissée telle quelle ; on passe à la suivante.
final class SkippedPage extends PageAdjustment {
  const SkippedPage();
}

/// Fin de la reprise : les pages suivantes ne sont pas proposées.
final class StopAdjusting extends PageAdjustment {
  const StopAdjusting();
}

/// Présente une page (à partir de son original) et rend le choix de l'utilisateur.
typedef PageAdjuster = Future<PageAdjustment> Function(
  ScannedPage page,
  String title,
);

/// Reprend les pages d'un document une à une ; chaque page validée est enregistrée aussitôt, donc
/// conservée si l'utilisateur s'arrête en cours de route.
Future<void> adjustDocumentPages(
  DocumentRepository repo,
  String documentId,
  PageAdjuster adjust,
) async {
  final pages = repo.byId(documentId)?.pages ?? const <ScannedPage>[];
  for (final (i, page) in pages.indexed) {
    switch (await adjust(page, 'Page ${i + 1} sur ${pages.length}')) {
      case AdjustedPage(:final scan):
        await _savePage(repo, documentId, page, scan);
      case SkippedPage():
        continue;
      case StopAdjusting():
        return;
    }
  }
}

/// Ajuste une seule page d'un document, à partir de son original.
Future<void> adjustDocumentPage(
  BuildContext context,
  DocumentRepository repo,
  String documentId,
  ScannedPage page,
) async {
  final result = await adjustPageOnScreen(context, page, 'Ajuster la page');
  if (result case AdjustedPage(:final scan)) {
    await _savePage(repo, documentId, page, scan);
  }
}

/// Écran d'ajustement ouvert sur l'original de la page, cadrage et filtre précédents repris.
/// Avec [skippable], l'utilisateur peut passer la page ; revenir en arrière arrête la reprise.
Future<PageAdjustment> adjustPageOnScreen(
  BuildContext context,
  ScannedPage page,
  String title, {
  bool skippable = false,
}) async {
  // L'écran appelant a pu disparaître pendant la page précédente (document supprimé…).
  if (!context.mounted) return const StopAdjusting();
  var skipped = false;
  final scan = await Navigator.push<ScanResult>(
    context,
    MaterialPageRoute(
      builder: (_) => AdjustScreen(
        photoPath: page.originalPath,
        initialQuad: page.corners,
        initialFilter: page.filter,
        title: title,
        onSkip: skippable ? () => skipped = true : null,
      ),
    ),
  );
  if (scan != null) return AdjustedPage(scan);
  return skipped ? const SkippedPage() : const StopAdjusting();
}

Future<void> _savePage(
  DocumentRepository repo,
  String documentId,
  ScannedPage page,
  ScanResult scan,
) => repo.adjustPage(
  documentId,
  page.id,
  corners: scan.quad,
  filter: scan.filter,
  processedJpeg: scan.processedJpeg,
);
