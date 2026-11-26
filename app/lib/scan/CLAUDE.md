# Domaine `scan` (app) — caméra, recadrage, lecture locale du ticket

Contrepartie serveur : `server/…/receipt/`. Conception : `docs/design/scanner.md`, `docs/design/lecture-locale.md`,
`docs/design/scanner-mlkit.md`.

- `domain/` (pur Dart) : `Quad` (coins normalisés, ordre HG/HD/BD/BG comme le serveur), `Rotation`
  (quart de tour horaire, aligné serveur), `ScanMode` (Ticket = 1 page / Document) et `ScanSession`
  (pages prises, immuable), `Stability` (déclenchement auto), `QuadSmoother` (contour affiché en direct : lissé, tient bon
  aux ratés et aux images isolées), `ReceiptParser` (devine total, TVA, date,
  devise, commerçant), `ReceiptTextReader` (frontière OCR), `PageScanner` (frontière scanner système).
- `data/` : `DocumentScanner` (OpenCV sur l'appareil, paramètres alignés sur `OpenCvImageProcessor` serveur ;
  en direct, préfère le candidat proche du contour suivi),
  `MlkitReceiptTextReader` + `text_rows` (ML Kit, sans réseau), `MlKitPageScanner` (scanner de documents
  ML Kit, mode de base).
- `ui/` — parcours inspiré d'Adobe Scan (`docs/design/parcours-de-scan.md`) :
  `CameraScreen` (carrousel `ScanModeSelector`, pile `PageStack`, pas de revue par prise) →
  `ReviewScreen` (pages en grand, Recadrer / Pivoter / Filtres en vignettes / Supprimer / Ajouter) →
  `ScanCompleted`. `capture.dart` : `scan()` (Android : choix du mode, scanner ML Kit puis revue, repli
  sur `CameraScreen` s'il est indisponible ; iOS : caméra ; ordinateur : fichiers + revue),
  `scanAndSave()` (bouton central), `scanPages()` (ajout de pages, mode imposé).
  Modification de l'existant dans la même revue (`ReviewScreen.edit` : retour = abandon) :
  `readjustReceipt()` (dépense, sans Ajouter ; supprimer la page = supprimer la dépense) et
  `editDocument()` (pages du document ; `saveDocumentEdit()` reconnaît une page à sa photo d'origine :
  réajustée si changée, retirée si absente, ajoutée en fin si nouvelle).
  `AdjustScreen` (+ `CornerEditor`) ne sert plus qu'à Recadrer.

Invariants propres
- L'original n'est jamais modifié : recadrage, filtre et rotation produisent une copie. L'original est la
  photo brute de `CameraScreen`, ou l'image déjà recadrée rendue par le scanner ML Kit (qui ne fournit
  pas la photo brute) : cadre par défaut sur l'image entière (`CapturedPage.scanned`).
- Seuil « même document » partagé (`Quad.sameDocumentShift`) entre `QuadSmoother` et la détection en direct.
- Tout fonctionne hors-ligne ; pas d'OCR sur desktop (aucun lecteur injecté).

Tests : `test/scan/**` (images de `test/fixtures/`, géométrie et parseur en unitaires).
