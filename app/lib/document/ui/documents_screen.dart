import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/document_repository.dart';
import '../domain/document.dart';
import 'document_screen.dart';
import '../../shared/ui/format.dart';

/// Onglet Documents : scans de plusieurs pages (contrats, attestations…), distincts des dépenses.
class DocumentsScreen extends StatelessWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<DocumentRepository>();
    final documents = repo.documents;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            titleTextStyle: Theme.of(context).textTheme.headlineMedium,
            title: const Text('Documents'),
          ),
          if (documents.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyDocuments(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.62,
                ),
                itemCount: documents.length,
                itemBuilder: (context, i) => _DocumentCard(
                  document: documents[i],
                  onTap: () => _open(context, documents[i].id),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, String id) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => DocumentScreen(documentId: id)),
  );
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onTap});

  final ScannedDocument document;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = document.pages.length;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: PageThumbnail(path: document.cover?.processedPath)),
          const SizedBox(height: 8),
          Text(
            document.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '$count page${count > 1 ? 's' : ''} · ${formatDate(document.updatedAt.toLocal())}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Vignette d'une page, comme une feuille posée : coins arrondis et légère ombre.
class PageThumbnail extends StatelessWidget {
  const PageThumbnail({super.key, required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final file = path == null ? null : File(path!);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox.expand(
          child: file != null && file.existsSync()
              ? Semantics(
                  label: 'Page scannée',
                  image: true,
                  child: Image.file(
                    file,
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, _, _) => const _MissingPage(),
                  ),
                )
              : const _MissingPage(),
        ),
      ),
    );
  }
}

class _MissingPage extends StatelessWidget {
  const _MissingPage();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainer,
    child: const Center(child: Icon(Icons.description_outlined)),
  );
}

class _EmptyDocuments extends StatelessWidget {
  const _EmptyDocuments();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            child: Icon(
              Icons.layers_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text('Aucun document', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Contrats, attestations, factures de plusieurs pages : '
            'touchez Scanner, enchaînez les pages, puis partagez-les en PDF.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
