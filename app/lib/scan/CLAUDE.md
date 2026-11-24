# Domaine `scan` (app) — caméra, recadrage, lecture locale du ticket

Contrepartie serveur : `server/…/receipt/`. Conception : `docs/design/scanner.md`, `docs/design/lecture-locale.md`.

- `domain/` (pur Dart) : `Quad` (coins normalisés, ordre HG/HD/BD/BG comme le serveur), `Rotation`
  (quart de tour horaire, aligné serveur), `ScanMode` (Ticket = 1 page / Document) et `ScanSession`
  (pages prises, immuable), `Stability` (déclenchement auto), `ReceiptParser` (devine total, TVA, date,
  devise, commerçant), `ReceiptTextReader` (frontière OCR).
- `data/` : `DocumentScanner` (OpenCV sur l'appareil, paramètres alignés sur `OpenCvImageProcessor` serveur),
  `MlkitReceiptTextReader` + `text_rows` (ML Kit, sans réseau).
- `ui/` — parcours inspiré d'Adobe Scan (`docs/design/parcours-de-scan.md`) :
  `CameraScreen` (carrousel `ScanModeSelector`, pile `PageStack`, pas de revue par prise) →
  `ReviewScreen` (pages en grand, Recadrer / Pivoter / Filtres en vignettes / Supprimer / Ajouter) →
  `ScanCompleted`. `capture.dart` : `scan()` (caméra sur mobile, fichiers + revue sur ordinateur),
  `scanAndSave()` (bouton central), `scanPages()` (ajout de pages, mode imposé), réajustements.
  `AdjustScreen` (+ `CornerEditor`) sert à Recadrer et à réajuster une dépense ou une page existante.

Invariants propres
- La photo brute n'est jamais modifiée : recadrage, filtre et rotation produisent une copie.
- Tout fonctionne hors-ligne ; pas d'OCR sur desktop (aucun lecteur injecté).

Tests : `test/scan/**` (images de `test/fixtures/`, géométrie et parseur en unitaires).
