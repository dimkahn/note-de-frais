import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/expense.dart';

/// Vignette ou image pleine du justificatif : version traitée si disponible, sinon l'original.
class ReceiptImage extends StatelessWidget {
  const ReceiptImage({
    super.key,
    required this.expense,
    this.showOriginal = false,
    this.fit = BoxFit.cover,
  });

  final Expense expense;
  final bool showOriginal;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final path = showOriginal
        ? expense.originalPath
        : (expense.processedPath ?? expense.originalPath);
    final label = showOriginal
        ? 'Photo originale du justificatif'
        : 'Justificatif recadré et amélioré';
    if (path == null || !File(path).existsSync()) {
      return Semantics(
        label: 'Image non disponible',
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: Icon(Icons.receipt_long_outlined)),
        ),
      );
    }
    return Semantics(
      label: label,
      image: true,
      child: Image.file(
        File(path),
        fit: fit,
        gaplessPlayback: true,
        cacheWidth: fit == BoxFit.cover ? 200 : null,
      ),
    );
  }
}
