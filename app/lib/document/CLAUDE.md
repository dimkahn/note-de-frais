# Domaine `document` (app) — documents multi-pages

Contrepartie serveur : `server/…/document/`. Conception : `docs/design/documents.md`.

- `domain/document.dart` : `ScannedDocument`, `ScannedPage` (original brut + rendu recadré/filtré).
- `data/` : `DocumentRepository`, `DocumentApi` (`/api/documents`), `DocumentSyncService` (même modèle que
  la synchro des dépenses ; envoie original **et** rendu calculé sur l'appareil).
- `ui/` : onglet Documents (`documents_screen`) et fiche (`document_screen` : pages, ajout, retrait, renommage, export).

Invariants propres
- Pas d'analyse : le rendu est calculé par `scan/` sur l'appareil.
- Page retirée = retirée de la liste, ses fichiers restent ; document supprimé = `deleted` logique.
- UUID client pour document et pages.

Tests : `test/document/**`, `test/scan/ui/adjust_pages_test.dart` (ajout de pages).
