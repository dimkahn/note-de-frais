# Scanner ML Kit sur Android

## Besoin
La détection de contour OpenCV échoue sur fond clair ou texturé (1 image réelle sur 6 : couette, drap,
moquette…). Sur Android, la prise de vue passe par le scanner de documents de Google
(`google_mlkit_document_scanner`, modèle ML des services Google Play), fiable sur ces fonds.

- Ticket sur une couette, mode Ticket → une page recadrée → une dépense.
- Mode Document, 3 pages scannées → un document de 3 pages.
- Pas de services Google Play, ou échec du scanner → la caméra maison (`CameraScreen`) prend le relais.
- iOS et ordinateur : inchangés.

## Parcours (Android)
1. Feuille de choix Ticket / Document (sauf mode imposé, ex. ajout de pages à un document).
2. Scanner ML Kit en mode de base (recadrer, pivoter ; pas de filtres ML Kit), sortie JPEG, import
   galerie autorisé ; limite d'une page en mode Ticket.
3. Notre `ReviewScreen` comme aujourd'hui (filtres en vignettes, Supprimer, Ajouter → relance le scanner).
4. Retour arrière depuis la revue d'un document : le scanner se rouvre en gardant les pages ; l'annuler
   à son tour abandonne le scan. Après « Ajouter », une annulation ramène à la revue. Ticket : retour =
   abandon.

## Invariants
- **Original intact** : ML Kit ne rend pas la photo brute, seulement des pages recadrées. L'original est
  l'image rendue par le scanner, copiée telle quelle et jamais modifiée ; filtre, rotation et recadrage
  produisent une copie. On ne peut pas recadrer plus large que ce que ML Kit a gardé.
- UUID client, `userEdited`, suppression logique : non concernés.

## Modèle, API, synchro
- Aucun changement de schéma ni d'API. Une page ML Kit = `CapturedPage(photoPath: image ML Kit,
  corners: image entière)` : pas de détection OpenCV sur la photo.
- Hors-ligne : le scan fonctionne sans réseau, sauf au tout premier usage (téléchargement du module par
  les services Google Play) → repli sur la caméra maison.

## Couches (`scan`)
- `domain/page_scanner.dart` : frontière `PageScanner` (`scan(pageLimit)` → chemins des images, `null` si
  abandon).
- `data/mlkit_page_scanner.dart` : implémentation ML Kit.
- `ui/capture.dart` : `scan()` choisit ML Kit sur Android, sinon la caméra ; la boucle pages → revue →
  ajouter de `_scanFiles` est généralisée à une source de pages (fichiers sur ordinateur, ML Kit).
- `CameraScreen` et la détection OpenCV en direct restent pour iOS et en secours.

## Tests
1. Une page du scanner → `CapturedPage` cadrée sur l'image entière.
2. Mode Ticket → limite 1 page ; Document → sans limite.
3. Scanner abandonné → `scan()` renvoie `null`.
4. Pages du scanner → revue → enregistrement : `ScanCompleted` avec ces pages.
5. « Ajouter » dans la revue relance le scanner et ajoute les pages.
6. Scanner indisponible (exception) → caméra maison.

## Alternatives écartées
- OpenCV combiné (segments + régions + arbitrage) : 4 images sur 6 au mieux, plafond trop bas.
- Modèle ML embarqué maison : plus long, alourdit l'APK.
- ML Kit en mode complet sans notre revue : parcours différent d'iOS/ordinateur, nos filtres perdus.
