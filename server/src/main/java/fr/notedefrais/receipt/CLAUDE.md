# Domaine `receipt` (serveur) — traitement d'image et lecture du justificatif

Contrepartie app : `app/lib/scan/` (même pipeline exécuté sur l'appareil, hors-ligne).

- `imaging/` : `ImageProcessor` (interface métier) et `OpenCvImageProcessor` (orientation EXIF → contour
  imposé ou détecté → perspective → filtre). `Quad` = 4 coins normalisés 0..1 (HG, HD, BD, BG).
  `ImageFilter` (filtres de netteté) est utilisé aussi par `expense` et `document`.
  Les paramètres sont alignés sur `app/lib/scan/data/document_scanner.dart` : modifier les deux ensemble.
- `extraction/` : `ReceiptExtractor` (interface), `ClaudeReceiptExtractor` (seul usage du SDK Anthropic,
  sortie structurée `ReceiptData` → `ReceiptFields`), `DisabledReceiptExtractor` sans clé.

Invariants propres
- N'altère jamais l'entrée : produit un nouveau JPEG (`ProcessedImage`).
- Clé Anthropic uniquement depuis l'environnement ; ni clé ni contenu de ticket dans les logs.
- Ne dépend d'aucun service métier : appelé par `expense/ExpenseProcessor`.

Tests : `OpenCvImageProcessorTest` (images synthétiques, `TestImages`), `QuadTest`,
`ClaudeReceiptExtractorTest` (HTTP simulé), `ReceiptDataTest`.
