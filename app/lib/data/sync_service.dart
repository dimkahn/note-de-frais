import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/expense.dart';
import 'expense_api.dart';
import 'file_store.dart';
import 'local_store.dart';

final class SyncReport {
  const SyncReport({
    this.pushed = 0,
    this.pulled = 0,
    this.errors = const [],
    this.offline = false,
    this.unauthorized = false,
    this.refusedForQuota = 0,
  });

  final int pushed;
  final int pulled;
  final List<String> errors;

  /// Le serveur était injoignable : rien n'est perdu, tout sera rejoué.
  final bool offline;

  /// La session a été refusée : il faut se reconnecter ; les changements locaux attendent.
  final bool unauthorized;

  /// Captures refusées faute d'espace en ligne : elles restent sur l'appareil, en attente d'envoi.
  final int refusedForQuota;
}

/// Synchronisation rejouable : on pousse d'abord les changements locaux (la base locale fait foi
/// tant qu'ils ne sont pas envoyés), puis on récupère les changements du serveur.
final class SyncService {
  SyncService({required this._store, required this._api, required this._files});

  final LocalStore _store;
  final ExpenseApi _api;
  final FileStore _files;

  /// Marge pour ne manquer aucune modification faite à la même milliseconde.
  static const _overlap = Duration(seconds: 1);

  Future<SyncReport> sync() async {
    var pushed = 0, pulled = 0, refusedForQuota = 0;
    final errors = <String>[];
    try {
      for (final local in await _store.pendingSync()) {
        try {
          await _push(local);
          pushed++;
        } on QuotaExceededException {
          refusedForQuota++; // reste en attente d'envoi : retentée à la prochaine synchro
        } on ApiException catch (e) {
          errors.add('${local.id} : $e');
        }
      }
      pulled = await _pull(errors);
    } on OfflineException {
      return SyncReport(
        pushed: pushed,
        pulled: pulled,
        errors: errors,
        offline: true,
        refusedForQuota: refusedForQuota,
      );
    } on UnauthorizedException {
      return SyncReport(
        pushed: pushed,
        pulled: pulled,
        errors: errors,
        unauthorized: true,
        refusedForQuota: refusedForQuota,
      );
    }
    return SyncReport(
      pushed: pushed,
      pulled: pulled,
      errors: errors,
      refusedForQuota: refusedForQuota,
    );
  }

  Future<void> _push(Expense local) async {
    switch (local.syncState) {
      case SyncState.synced:
        return;
      case SyncState.pendingUpload:
        final file = File(local.originalPath!);
        var remote = await _api.upload(
          local,
          await file.readAsBytes(),
          _contentType(file.path),
        );
        if (local.userEdited) remote = await _api.update(local);
        await _store.save(_merge(remote, local));
      case SyncState.pendingUpdate:
        await _store.save(_merge(await _api.update(local), local));
      case SyncState.pendingReprocess:
        await _store.save(
          _merge(
            await _api.reprocess(local.id, local.filter, local.corners),
            local,
          ),
        );
      case SyncState.pendingDelete:
        await _api.delete(local.id);
        await _store.save(local.copyWith(syncState: SyncState.synced));
    }
  }

  Future<int> _pull(List<String> errors) async {
    final lastSync = await _store.lastSync();
    final changes = await _api.changesSince(lastSync?.subtract(_overlap));
    var newest = lastSync;
    var pulled = 0;
    for (final remote in changes) {
      final local = await _store.get(remote.id);
      if (local != null && local.syncState != SyncState.synced) {
        continue; // changement local en attente
      }
      try {
        await _store.save(await _withImages(remote, local));
        pulled++;
      } on ApiException catch (e) {
        errors.add('${remote.id} : $e');
      }
      final at = remote.serverUpdatedAt;
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    if (newest != null) await _store.setLastSync(newest);
    return pulled;
  }

  /// Télécharge ce qui manque localement : l'original (dépense venue d'un autre appareil)
  /// et l'image traitée quand elle a changé.
  Future<Expense> _withImages(Expense remote, Expense? local) async {
    var merged = _merge(remote, local);
    if (remote.deleted) return merged;

    if (merged.originalPath == null) {
      final original = await _api.originalImage(remote.id);
      final file = await _files.saveOriginalBytes(
        remote.id,
        original.bytes,
        _extension(original.contentType),
      );
      merged = merged.copyWith(originalPath: file.path);
    }
    final processedChanged =
        local?.processedPath == null ||
        local?.serverUpdatedAt != remote.serverUpdatedAt;
    if (remote.hasProcessedImage && processedChanged) {
      final file = await _files.saveProcessed(
        remote.id,
        await _api.processedImage(remote.id),
      );
      merged = merged.copyWith(processedPath: file.path);
    }
    return merged;
  }

  /// État du serveur + chemins des fichiers locaux. Le pré-remplissage de l'appareil reste affiché
  /// tant que le serveur n'a pas terminé son analyse ; ensuite, le serveur fait foi.
  static Expense _merge(Expense remote, Expense? local) {
    final merged = remote.copyWith(
      syncState: SyncState.synced,
      originalPath: local?.originalPath,
      processedPath: local?.processedPath,
    );
    return local != null && local.prefilled
        ? merged.withDeviceGuess(local.guess)
        : merged;
  }

  static String _contentType(String path) =>
      switch (p.extension(path).toLowerCase()) {
        '.png' => 'image/png',
        '.webp' => 'image/webp',
        '.heic' => 'image/heic',
        _ => 'image/jpeg',
      };

  static String _extension(String contentType) =>
      switch (contentType.split(';').first.trim()) {
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/heic' => 'heic',
        _ => 'jpg',
      };
}
