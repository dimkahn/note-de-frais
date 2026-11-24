# Domaine `scan` (app) — caméra, recadrage, lecture locale du ticket

Contrepartie serveur : `server/…/receipt/`. Conception : `docs/design/scanner.md`, `docs/design/lecture-locale.md`.

- `domain/` (pur Dart) : `Quad` (coins normalisés, ordre HG/HD/BD/BG comme le serveur), `Stability`
  (déclenchement auto), `ReceiptParser` (devine total, TVA, date, devise, commerçant), `ReceiptTextReader` (frontière OCR).
- `data/` : `DocumentScanner` (OpenCV sur l'appareil, paramètres alignés sur `OpenCvImageProcessor` serveur),
  `MlkitReceiptTextReader` + `text_rows` (ML Kit, sans réseau).
- `ui/` : `CameraScreen`, `AdjustScreen`, `CornerEditor`, `capture.dart` (parcours d'ajout vers
  `ExpenseRepository` / `DocumentRepository`).

Invariants propres
- La photo brute n'est jamais modifiée : recadrage et filtres produisent une copie.
- Tout fonctionne hors-ligne ; pas d'OCR sur desktop (aucun lecteur injecté).

Tests : `test/scan/**` (images de `test/fixtures/`, géométrie et parseur en unitaires).
