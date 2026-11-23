# Scanner de justificatifs façon « Adobe Scan »

## Besoin
Capturer un justificatif comme Adobe Scan : contour du document détecté en direct, déclenchement
automatique quand le cadrage est stable, ajustement manuel des 4 coins, aperçu des filtres,
fonctionnement hors-ligne — **sans jamais perdre la photo brute** (invariant « original intact »).

Critères d'acceptation
- Étant donné la caméra ouverte devant un ticket, le contour s'affiche et suit le document.
- Quand le contour reste stable ~1 s, la photo est prise automatiquement (désactivable).
- Après la prise, je peux déplacer chaque coin ; les coins restent dans l'image et le quadrilatère reste convexe.
- Je vois l'aperçu recadré avec le filtre choisi avant de valider ; tout cela sans réseau.
- Après validation : la photo brute est stockée telle quelle ; l'image recadrée est visible tout de suite ;
  le serveur reçoit l'original **et** les coins choisis et produit la même découpe.
- Sur desktop ou sans caméra : choix d'une image dans la galerie, puis même écran d'ajustement.

## Invariants touchés
- Original intact : la photo brute est copiée sans modification ; recadrage et filtre produisent une copie.
- `userEdited` / suppression logique / UUID client : inchangés.

## Modèle
- `Quad` : 4 coins **normalisés** (0..1) dans le repère de l'image *orientée* (EXIF appliqué),
  ordre haut-gauche, haut-droit, bas-droit, bas-gauche. Sérialisé `"x1,y1,x2,y2,x3,y3,x4,y4"`.
  Normalisé ⇒ indépendant de la résolution (aperçu basse définition, photo pleine définition, serveur).
- Serveur : colonne `corners` (texte, nullable) sur `expense`.
- App : colonne `corners` ; migration SQLite v1 → v2 (`ALTER TABLE ... ADD COLUMN`).

## API (rétrocompatible)
- `POST /api/expenses` : paramètre optionnel `corners`. Absent ⇒ détection automatique (comportement actuel).
- `POST /api/expenses/{id}/reprocess` : `corners` optionnel ; sinon réutilise ceux enregistrés.
- `corners` invalide (≠ 8 nombres, hors [0,1], non convexe) ⇒ `400`.
- `ExpenseDto.corners` ajouté.

## Hors-ligne / synchro
Tout se passe sur l'appareil (détection, découpe, filtre) ; l'image traitée locale est disponible
immédiatement. La synchro envoie original + coins + filtre ; l'image traitée serveur (pleine
définition, même algorithme) remplace ensuite la copie locale.

## Couches
- `app/lib/domain/quad.dart` : géométrie pure (ordre, convexité, aire, rotation selon l'orientation
  du capteur, (dé)sérialisation, contrainte de déplacement d'un coin).
- `app/lib/domain/stability.dart` : détecteur de stabilité pour le déclenchement automatique.
- `app/lib/scan/document_scanner.dart` : OpenCV sur l'appareil (`opencv_dart`) — détection, découpe, filtres.
  Mêmes paramètres que `server/.../OpenCvImageProcessor` (duplication assumée Java/Dart, documentée des deux côtés).
- `app/lib/scan/` : écrans caméra et ajustement ; `CornerEditor` widget.
- Serveur : `ImageProcessor.process(original, filter, corners)` ; `Quad` record + validation.

## Plan de tests (ordre TDD)
Serveur : Quad (parse/validation) → processeur avec coins imposés → service (coins stockés, réutilisés au retraitement) → contrôleur (400 si invalide).
App : Quad → StabilityTracker → DocumentScanner (images synthétiques) → Expense/LocalStore (migration v2) →
API/synchro (coins envoyés) → repository.captureScan → CornerEditor (widget) → écran d'ajustement.

## Alternatives écartées
- ML Kit Document Scanner : expérience identique en peu de code, mais ne fournit pas la photo brute.
- Détection uniquement côté serveur : impossible hors-ligne et pas de retour en direct.

## Hors périmètre (YAGNI pour l'instant)
Documents multipages.
