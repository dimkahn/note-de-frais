import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/expense_repository.dart';
import '../domain/expense.dart';

/// Parcours d'ajout : source (appareil photo / galerie) → filtre → enregistrement local.
Future<Expense?> captureReceipt(
  BuildContext context,
  ExpenseRepository repo,
) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (_) => const _SourceSheet(),
  );
  if (source == null || !context.mounted) return null;

  final XFile? photo;
  try {
    // Pleine résolution : le serveur recadre et l'original est conservé intact.
    photo = await ImagePicker().pickImage(
      source: source,
      requestFullMetadata: false,
    );
  } on Exception catch (e) {
    if (context.mounted) {
      _snack(context, 'Impossible d\'accéder à la photo : $e');
    }
    return null;
  }
  if (photo == null || !context.mounted) return null;

  final filter = await showDialog<ImageFilter>(
    context: context,
    builder: (_) => const FilterDialog(initial: ImageFilter.enhance),
  );
  if (filter == null) return null;

  final expense = await repo.capture(photo.path, filter);
  if (context.mounted) {
    final offline = repo.lastReport?.offline ?? true;
    _snack(
      context,
      offline
          ? 'Enregistré sur l\'appareil, envoi dès que possible'
          : 'Envoyé pour traitement',
    );
  }
  return expense;
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    final cameraAvailable = Platform.isAndroid || Platform.isIOS;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cameraAvailable)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Prendre une photo'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choisir une image'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}

/// Choix du filtre de netteté appliqué après le recadrage automatique.
class FilterDialog extends StatefulWidget {
  const FilterDialog({super.key, required this.initial});

  final ImageFilter initial;

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late ImageFilter _selected = widget.initial;

  static const _descriptions = {
    ImageFilter.none: 'Recadrage seul, couleurs d\'origine',
    ImageFilter.enhance: 'Contraste local et netteté (recommandé)',
    ImageFilter.sharpen: 'Accentuation forte pour les tickets flous',
    ImageFilter.scanBw: 'Noir et blanc type scanner, idéal pour l\'impression',
  };

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Amélioration de l\'image'),
    content: RadioGroup<ImageFilter>(
      groupValue: _selected,
      onChanged: (f) => setState(() => _selected = f ?? _selected),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final f in ImageFilter.values)
            RadioListTile<ImageFilter>(
              value: f,
              title: Text(f.label),
              subtitle: Text(_descriptions[f]!),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Annuler'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _selected),
        child: const Text('Valider'),
      ),
    ],
  );
}
