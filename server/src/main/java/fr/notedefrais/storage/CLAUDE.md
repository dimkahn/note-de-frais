# `storage` (serveur, transverse) — fichiers des justificatifs

- `FileStorage` (interface) / `LocalFileStorage` : `<racine>/<id>/original.<ext>` en écriture unique
  (`OriginalAlreadyExistsException`), `<id>/processed.jpg` remplaçable. Une instance par domaine
  (dépenses, documents), branchée dans `config/InfrastructureConfig`.
- Ne connaît aucun domaine. Jamais de suppression d'original.

Tests : `LocalFileStorageTest`.
