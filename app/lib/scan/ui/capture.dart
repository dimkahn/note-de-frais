import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../document/data/document_repository.dart';
import '../../expense/data/expense_repository.dart';
import '../../document/domain/document.dart';
import '../../expense/domain/expense.dart';

import 'package:provider/provider.dart';

import '../data/mlkit_page_scanner.dart';
import '../domain/page_scanner.dart';
import '../domain/scan_session.dart';
import 'adjust_screen.dart';
import 'camera_screen.dart';
import 'review_screen.dart';

/// Scan jusqu'à la revue : scanner système ([pageScanner], ML Kit par défaut sur Android), sinon
/// caméra maison sur mobile (mode choisi dans la visée, sauf [modeLocked]), fichiers sur ordinateur.
/// `null` si l'utilisateur abandonne.
Future<ScanCompleted?> scan(
  BuildContext context, {
  ScanMode mode = ScanMode.ticket,
  bool modeLocked = false,
  PageScanner? pageScanner,
  Compute compute = inIsolate,
}) async {
  final scanner =
      pageScanner ?? (Platform.isAndroid ? const MlKitPageScanner() : null);
  if (scanner == null && (Platform.isAndroid || Platform.isIOS)) {
    return _camera(context, mode, modeLocked: modeLocked);
  }
  final chosen = modeLocked ? mode : await _chooseMode(context, mode);
  if (chosen == null || !context.mounted) return null;
  if (scanner == null) return _scanFrom(context, chosen, _pickFiles, compute);
  final messenger = ScaffoldMessenger.maybeOf(context);
  var firstPass = true;
  // Indisponible d'emblée : la caméra de l'application. En cours de session : retour à la revue,
  // sans perdre les pages déjà scannées.
  Future<List<CapturedPage>> source(ScanMode mode) async {
    try {
      return await _fromScanner(scanner, mode);
    } on PageScannerUnavailable catch (e) {
      if (firstPass) rethrow;
      debugPrint('$e');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Scanner indisponible, réessayez')),
      );
      return const [];
    } finally {
      firstPass = false;
    }
  }

  try {
    return await _scanFrom(context, chosen, source, compute);
  } on PageScannerUnavailable catch (e) {
    debugPrint('$e : caméra de l\'application à la place');
    if (!context.mounted) return null;
    return _camera(context, chosen, modeLocked: true);
  }
}

Future<ScanCompleted?> _camera(
  BuildContext context,
  ScanMode mode, {
  required bool modeLocked,
}) => Navigator.push<ScanCompleted>(
  context,
  MaterialPageRoute(
    builder: (_) => CameraScreen(initialMode: mode, modeLocked: modeLocked),
  ),
);

/// Pages à ajouter à une session dans [mode] ; liste vide si l'utilisateur abandonne.
typedef PageSource = Future<List<CapturedPage>> Function(ScanMode mode);

Future<List<CapturedPage>> _fromScanner(
  PageScanner scanner,
  ScanMode mode,
) async => [
  for (final path in await scanner.scan(pageLimit: mode.pageLimit) ?? [])
    CapturedPage.scanned(path),
];

Future<List<CapturedPage>> _pickFiles(ScanMode mode) async {
  final picker = ImagePicker();
  final photos = mode == ScanMode.document
      ? await picker.pickMultiImage(requestFullMetadata: false)
      : [
          ?await picker.pickImage(
            source: ImageSource.gallery,
            requestFullMetadata: false,
          ),
        ];
  return [for (final photo in photos) CapturedPage(photoPath: photo.path)];
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

/// Pages de [source] puis revue, autant de fois que l'utilisateur ajoute des pages.
Future<ScanCompleted?> _scanFrom(
  BuildContext context,
  ScanMode mode,
  PageSource source,
  Compute compute,
) async {
  var session = ScanSession(mode);
  // Retour arrière depuis la revue d'un document : la source est rouverte en gardant les pages ;
  // l'abandonner à son tour abandonne le scan.
  var reopenedAfterBack = false;
  while (context.mounted) {
    if (session.canAdd) {
      final added = await source(mode);
      if (added.isEmpty && reopenedAfterBack) return null;
      for (final page in added) {
        if (session.canAdd) session = session.withPage(page);
      }
    }
    reopenedAfterBack = false;
    if (session.pages.isEmpty || !context.mounted) return null;
    final outcome = await Navigator.push<ReviewOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen(session: session, compute: compute),
      ),
    );
    switch (outcome) {
      case ReviewSaved(:final pages):
        return ScanCompleted(mode, pages);
      case ReviewContinue(session: final remaining, addMore: true):
        session = remaining;
      case ReviewContinue(session: final remaining)
          when mode == ScanMode.document && remaining.pages.isNotEmpty:
        session = remaining;
        reopenedAfterBack = true;
      case _:
        return null; // ticket, dernière page supprimée : abandon
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

/// Modifie le justificatif d'une dépense dans la revue, à partir de son original. Supprimer sa
/// page revient à supprimer la dépense : [onDelete] (qui demande confirmation).
Future<void> readjustReceipt(
  BuildContext context,
  ExpenseRepository repo,
  Expense e, {
  required Future<void> Function() onDelete,
  Compute compute = inIsolate,
}) async {
  final original = e.originalPath;
  if (original == null || !File(original).existsSync()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Original pas encore disponible sur cet appareil'),
      ),
    );
    return;
  }
  final outcome = await Navigator.push<ReviewOutcome>(
    context,
    MaterialPageRoute(
      builder: (_) => ReviewScreen.edit(
        session: const ScanSession(ScanMode.ticket).withPage(
          CapturedPage(
            photoPath: original,
            corners: e.corners,
            filter: e.filter,
            rotation: e.rotation,
          ),
        ),
        compute: compute,
      ),
    ),
  );
  switch (outcome) {
    case ReviewSaved(pages: [final scan]):
      if (scan.quad == e.corners &&
          scan.filter == e.filter &&
          scan.rotation == e.rotation) {
        return;
      }
      await repo.reprocess(
        e.id,
        scan.filter,
        corners: scan.quad,
        rotation: scan.rotation,
        processedJpeg: scan.processedJpeg,
      );
    case ReviewContinue():
      if (context.mounted) await onDelete();
    case _:
      return;
  }
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

/// Applique au document l'issue de sa revue. Une page est reconnue à sa photo d'origine : celles
/// modifiées sont réajustées, celles absentes retirées, les photos inconnues ajoutées à la fin.
Future<void> saveDocumentEdit(
  DocumentRepository repo,
  String documentId,
  List<ScannedPage> before,
  List<ScanResult> pages,
) async {
  final reviewed = {for (final p in pages) p.photoPath: p};
  for (final page in before) {
    final scan = reviewed[page.originalPath];
    if (scan == null) {
      await repo.removePage(documentId, page.id);
    } else if (_changed(page, scan)) {
      await _savePage(repo, documentId, page, scan);
    }
  }
  final known = {for (final p in before) p.originalPath};
  final added = [
    for (final p in pages)
      if (!known.contains(p.photoPath)) p,
  ];
  if (added.isNotEmpty) await repo.addPages(documentId, _captures(added));
}

bool _changed(ScannedPage page, ScanResult scan) =>
    scan.quad != page.corners ||
    scan.filter != page.filter ||
    scan.rotation != page.rotation;

/// Modifie les pages d'un document dans la revue, ouverte sur [initialPage].
Future<void> editDocument(
  BuildContext context,
  DocumentRepository repo,
  String documentId, {
  int initialPage = 0,
  PageScanner? pageScanner,
  Compute compute = inIsolate,
}) async {
  final doc = repo.byId(documentId);
  if (doc == null) return;
  var session = ScanSession(
    ScanMode.document,
    pages: [
      for (final p in doc.pages)
        CapturedPage(
          photoPath: p.originalPath,
          corners: p.corners,
          filter: p.filter,
          rotation: p.rotation,
        ),
    ],
  );
  final source = _pageSource(context, pageScanner);
  var page = initialPage;
  while (true) {
    if (!context.mounted) return;
    final outcome = await Navigator.push<ReviewOutcome>(
      context,
      MaterialPageRoute(
        builder: (_) => ReviewScreen.edit(
          session: session,
          initialPage: page,
          compute: compute,
        ),
      ),
    );
    switch (outcome) {
      case ReviewSaved(:final pages):
        return saveDocumentEdit(repo, documentId, doc.pages, pages);
      case ReviewContinue(session: final kept, addMore: true):
        if (!context.mounted) return;
        final added = await source(ScanMode.document);
        session = added.fold(kept, (s, p) => s.withPage(p));
        page = added.isEmpty ? 0 : kept.pages.length;
      // En modification, la revue ne rend ce cas qu'à la suppression de la dernière page.
      case ReviewContinue():
        if (!context.mounted) return;
        if (await _confirmRemoveAll(context, session.pages.length)) {
          return saveDocumentEdit(repo, documentId, doc.pages, const []);
        }
        // Annulé : la revue est rouverte, pages remises.
        page = 0;
      case null:
        return;
    }
  }
}

Future<bool> _confirmRemoveAll(BuildContext context, int count) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          count > 1 ? 'Retirer les $count pages ?' : 'Retirer la page ?',
        ),
        content: const Text('Les photos d\'origine restent sur l\'appareil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    ) ??
    false;

/// D'où viennent les pages ajoutées pendant une modification : scanner système, sinon caméra de
/// l'application sur mobile, fichiers sur ordinateur. Liste vide si rien n'est pris.
PageSource _pageSource(BuildContext context, PageScanner? pageScanner) {
  final scanner =
      pageScanner ?? (Platform.isAndroid ? const MlKitPageScanner() : null);
  if (scanner != null) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    return (mode) async {
      try {
        return await _fromScanner(scanner, mode);
      } on PageScannerUnavailable catch (e) {
        debugPrint('$e');
        messenger?.showSnackBar(
          const SnackBar(content: Text('Scanner indisponible, réessayez')),
        );
        return const [];
      }
    };
  }
  if (Platform.isAndroid || Platform.isIOS) {
    return (mode) async => [
      for (final s
          in (await _camera(context, mode, modeLocked: true))?.pages ??
              const <ScanResult>[])
        CapturedPage(
          photoPath: s.photoPath,
          corners: s.quad,
          filter: s.filter,
          rotation: s.rotation,
        ),
    ];
  }
  return _pickFiles;
}
