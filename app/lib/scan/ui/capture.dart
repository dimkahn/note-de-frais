import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../document/data/document_repository.dart';
import '../../expense/data/expense_repository.dart';
import '../../document/domain/document.dart';
import '../../expense/domain/expense.dart';

import 'package:provider/provider.dart';

import '../domain/scan_session.dart';
import 'adjust_screen.dart';
import 'camera_screen.dart';
import 'review_screen.dart';

/// Scan jusqu'à la revue : caméra sur mobile (mode choisi dans la visée, sauf [modeLocked]),
/// fichiers sur ordinateur. `null` si l'utilisateur abandonne.
Future<ScanCompleted?> scan(
  BuildContext context, {
  ScanMode mode = ScanMode.ticket,
  bool modeLocked = false,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return Navigator.push<ScanCompleted>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(initialMode: mode, modeLocked: modeLocked),
      ),
    );
  }
  final chosen = modeLocked ? mode : await _chooseMode(context, mode);
  if (chosen == null || !context.mounted) return null;
  return _scanFiles(context, chosen);
}

/// Sans caméra, le mode se choisit avant de prendre les fichiers.
Future<ScanMode?> _chooseMode(BuildContext context, ScanMode current) =>
    showModalBottomSheet<ScanMode>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in ScanMode.values)
              ListTile(
                leading: Icon(
                  m == ScanMode.ticket
                      ? Icons.receipt_long_outlined
                      : Icons.layers_outlined,
                ),
                title: Text(m.label),
                subtitle: Text(
                  m == ScanMode.ticket
                      ? 'Une image, une dépense'
                      : 'Plusieurs pages, un document',
                ),
                selected: m == current,
                onTap: () => Navigator.pop(context, m),
              ),
          ],
        ),
      ),
    );

/// Fichiers puis revue, autant de fois que l'utilisateur ajoute des pages.
Future<ScanCompleted?> _scanFiles(BuildContext context, ScanMode mode) async {
  var session = ScanSession(mode);
  final picker = ImagePicker();
  while (context.mounted) {
    if (session.canAdd) {
      final photos = mode == ScanMode.document
          ? await picker.pickMultiImage(requestFullMetadata: false)
          : [
              ?await picker.pickImage(
                source: ImageSource.gallery,
                requestFullMetadata: false,
              ),
            ];
      for (final photo in photos) {
        if (session.canAdd) {
          session = session.withPage(CapturedPage(photoPath: photo.path));
        }
      }
    }
    if (session.pages.isEmpty || !context.mounted) return null;
    final outcome = await Navigator.push<ReviewOutcome>(
      context,
      MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
    );
    switch (outcome) {
      case ReviewSaved(:final pages):
        return ScanCompleted(mode, pages);
      case ReviewContinue(session: final remaining) when remaining.canAdd:
        session = remaining;
      case _:
        return null; // retour sur un ticket déjà pris : abandon
    }
  }
  return null;
}

/// Ce que le scan a créé.
sealed class SavedScan {
  const SavedScan();
}

final class SavedExpense extends SavedScan {
  const SavedExpense(this.expense);

  final Expense expense;
}

final class SavedDocument extends SavedScan {
  const SavedDocument(this.document);

  final ScannedDocument document;
}

/// Bouton Scanner : scan dans [mode] (modifiable dans la visée), puis enregistrement local
/// d'une dépense (ticket) ou d'un nouveau document.
Future<SavedScan?> scanAndSave(BuildContext context, ScanMode mode) async {
  final done = await scan(context, mode: mode);
  if (done == null || done.pages.isEmpty || !context.mounted) return null;
  final expenses = context.read<ExpenseRepository>();
  final documents = context.read<DocumentRepository>();
  final messenger = ScaffoldMessenger.of(context);
  return switch (done.mode) {
    ScanMode.ticket => SavedExpense(
      await _saveReceipt(expenses, messenger, done.pages.single),
    ),
    ScanMode.document => SavedDocument(
      await documents.create(_captures(done.pages)),
    ),
  };
}

Future<Expense> _saveReceipt(
  ExpenseRepository repo,
  ScaffoldMessengerState messenger,
  ScanResult scan,
) async {
  final expense = await repo.captureScan(
    scan.photoPath,
    scan.quad,
    scan.filter,
    processedJpeg: scan.processedJpeg,
    rotation: scan.rotation,
  );
  final message = !repo.withServer
      ? 'Enregistré sur l\'appareil'
      : (repo.lastReport?.offline ?? true)
      ? 'Enregistré sur l\'appareil, envoi dès que possible'
      : 'Envoyé pour extraction';
  messenger.showSnackBar(SnackBar(content: Text(message)));
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
        initialRotation: e.rotation,
      ),
    ),
  );
  if (scan == null) return;
  await repo.reprocess(
    e.id,
    scan.filter,
    corners: scan.quad,
    rotation: scan.rotation,
    processedJpeg: scan.processedJpeg,
  );
}

/// Pages ajoutées à un document existant : scan en mode Document imposé.
/// Liste vide si l'utilisateur abandonne.
Future<List<PageCapture>> scanPages(BuildContext context) async {
  final done = await scan(context, mode: ScanMode.document, modeLocked: true);
  return done == null ? const [] : _captures(done.pages);
}

List<PageCapture> _captures(List<ScanResult> scans) => [
  for (final s in scans)
    PageCapture(
      photoPath: s.photoPath,
      corners: s.quad,
      filter: s.filter,
      rotation: s.rotation,
      processedJpeg: s.processedJpeg,
    ),
];

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
        initialRotation: page.rotation,
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
  rotation: scan.rotation,
  processedJpeg: scan.processedJpeg,
);
