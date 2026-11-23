import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/expense_repository.dart';
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
    scan = await Navigator.push<ScanResult>(
      context,
      MaterialPageRoute(builder: (_) => const CameraScreen()),
    );
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
    final message = !repo.settings.isConfigured
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
