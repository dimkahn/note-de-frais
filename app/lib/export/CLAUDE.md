# Domaine `export` (app) — PDF et photos

Pas de contrepartie serveur : l'export est local. Conception : `docs/design/documents.md`.

- `data/` : `ExportService` (PDF d'une note de frais ou d'un document, photos recadrées),
  `SystemFileSharer` (menu de partage, `share_plus`), `PlatformDownloadsFolder` (Téléchargements).
- `ui/` : `ExportButton` (menu « Exporter »), `report.dart` (`reportOf` : dépenses → `ExpenseReport`).

Invariants propres
- Exporte les rendus recadrés (ou l'original à défaut) ; ne modifie aucun fichier source.
- Totaux par devise, sans conversion.

Tests : `test/export/**` (`temp_downloads` dans `test/support/`).
