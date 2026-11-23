import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/document_repository.dart';
import '../domain/document.dart';
import 'capture.dart';
import 'documents_screen.dart';
import 'export_button.dart';

/// Fiche d'un document : pages numérotées, ajout, retrait, renommage, export.
class DocumentScreen extends StatelessWidget {
  const DocumentScreen({super.key, required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DocumentRepository>();
    final doc = repo.byId(documentId);
    if (doc == null || doc.deleted) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Document supprimé')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, overflow: TextOverflow.ellipsis),
        actions: [
          ExportButton(
            title: doc.title,
            imagePaths: [for (final p in doc.pages) p.processedPath],
          ),
          PopupMenuButton<String>(
            tooltip: 'Plus d\'options',
            onSelected: (action) => switch (action) {
              'rename' => _rename(context, repo, doc),
              _ => _delete(context, repo, doc),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(
                value: 'delete',
                child: Text('Supprimer le document'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPages(context, repo, doc),
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Ajouter des pages'),
      ),
      body: doc.pages.isEmpty
          ? const Center(child: Text('Aucune page'))
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.72,
              ),
              itemCount: doc.pages.length,
              itemBuilder: (context, i) => _PageTile(
                number: i + 1,
                page: doc.pages[i],
                onTap: () => _view(context, doc, i),
                onLongPress: () =>
                    _pageActions(context, repo, doc, doc.pages[i]),
              ),
            ),
    );
  }

  Future<void> _addPages(
    BuildContext context,
    DocumentRepository repo,
    ScannedDocument doc,
  ) async {
    final pages = await scanPages(context);
    if (pages.isNotEmpty) await repo.addPages(doc.id, pages);
  }

  void _view(BuildContext context, ScannedDocument doc, int index) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _PageViewer(documentId: doc.id, initialPage: index),
        ),
      );

  Future<void> _pageActions(
    BuildContext context,
    DocumentRepository repo,
    ScannedDocument doc,
    ScannedPage page,
  ) async {
    final remove = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Retirer la page'),
          subtitle: const Text('La photo d\'origine reste sur l\'appareil.'),
          onTap: () => Navigator.pop(context, true),
        ),
      ),
    );
    if (remove ?? false) await repo.removePage(doc.id, page.id);
  }

  Future<void> _rename(
    BuildContext context,
    DocumentRepository repo,
    ScannedDocument doc,
  ) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: doc.title),
    );
    if (title != null) await repo.rename(doc.id, title);
  }

  Future<void> _delete(
    BuildContext context,
    DocumentRepository repo,
    ScannedDocument doc,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer ce document ?'),
        content: Text('« ${doc.title} » et ses ${doc.pages.length} page(s).'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await repo.delete(doc.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}

class _PageTile extends StatelessWidget {
  const _PageTile({
    required this.number,
    required this.page,
    required this.onTap,
    required this.onLongPress,
  });

  final int number;
  final ScannedPage page;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Page $number',
      hint: 'Appui long pour retirer la page',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            Positioned.fill(child: PageThumbnail(path: page.processedPath)),
            Positioned(
              left: 8,
              bottom: 8,
              child: Container(
                constraints: const BoxConstraints(minWidth: 28),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titre du document, avec son propre contrôleur (libéré avec le dialogue).
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Renommer le document'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.sentences,
      decoration: const InputDecoration(labelText: 'Titre'),
      onSubmitted: (v) => Navigator.pop(context, v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('Renommer'),
      ),
    ],
  );
}

/// Lecture plein écran, page par page, avec zoom ; on peut y retirer la page affichée.
class _PageViewer extends StatefulWidget {
  const _PageViewer({required this.documentId, required this.initialPage});

  final String documentId;
  final int initialPage;

  @override
  State<_PageViewer> createState() => _PageViewerState();
}

class _PageViewerState extends State<_PageViewer> {
  late int _page = widget.initialPage;
  late final _controller = PageController(initialPage: widget.initialPage);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DocumentRepository>();
    final pages = repo.byId(widget.documentId)?.pages ?? const [];
    if (pages.isEmpty) return const Scaffold(body: SizedBox.shrink());
    final page = _page.clamp(0, pages.length - 1);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Page ${page + 1} sur ${pages.length}'),
        actions: [
          IconButton(
            tooltip: 'Retirer la page',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _remove(repo, pages[page]),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: pages.length,
        onPageChanged: (i) => setState(() => _page = i),
        itemBuilder: (_, i) => InteractiveViewer(
          maxScale: 6,
          child: Center(
            child: Semantics(
              label: 'Page ${i + 1}',
              image: true,
              child: Image.file(File(pages[i].processedPath)),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _remove(DocumentRepository repo, ScannedPage page) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer cette page ?'),
        content: const Text('La photo d\'origine reste sur l\'appareil.'),
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
    );
    if (!(ok ?? false)) return;
    await repo.removePage(widget.documentId, page.id);
    if (mounted) Navigator.pop(context);
  }
}
