# Parcours de scan inspiré d'Adobe Scan

Ergonomie inspirée d'Adobe Scan ; l'identité visuelle reste la nôtre (encre sur ticket).

## Besoin (critères d'acceptation)
- Étant donné n'importe quel onglet, quand j'appuie sur le bouton rond central **Scanner** de la barre
  du bas, alors la caméra s'ouvre — en mode **Document** depuis l'onglet Documents, **Ticket** sinon.
- Quand je glisse ou touche « Ticket » / « Document » sous la visée, alors le mode change.
  Ticket = une page ; Document = plusieurs pages enchaînées.
- En mode Document, chaque prise (recadrage automatique) s'empile en vignette dans le coin avec un
  compteur ; toucher la pile ouvre la revue. Pas de revue après chaque prise.
- **Revue** : page en grand, glisser pour changer de page (« 2 / 3 ») ; outils : Recadrer, Pivoter,
  Filtres (vignettes de la page filtrée), Supprimer, Ajouter (Document seulement, retour caméra).
  « Enregistrer » crée la dépense (retour sur Dépenses) ou le document (ouverture de sa fiche).
- « Ajouter des pages » depuis la fiche d'un document : caméra en mode Document, sans carrousel.
- Ordinateur (pas de caméra) : le bouton central propose Ticket / Document, puis le choix de
  fichiers, puis la même revue.
- Une rotation choisie est conservée : affichage, export, synchronisation, autre appareil, re-traitement serveur.

## Invariants
- Original intact : coins, filtre et rotation ne sont que des paramètres de rendu ; le rendu est une copie.
- UUID client, `userEdited`, suppression logique : inchangés.

## Rotation (de bout en bout)
Le serveur recalcule le rendu des dépenses depuis l'original et retrie les coins (`orderCorners`) :
une rotation par l'ordre des coins serait perdue. D'où un paramètre explicite.
- Sens : quart de tour **horaire**, appliqué **après** redressement et filtre. Valeurs 0, 90, 180, 270.
- Serveur : `Rotation` (enum, `receipt.imaging`) ; `ImageProcessor.process(original, filter, corners,
  rotation)`. Colonne `rotation` sur `expense` et `document_page` avec défaut 0 (`ddl-auto: update`
  sur des lignes existantes : la valeur par défaut est obligatoire).
- API : champ `rotation` (degrés, facultatif, défaut 0, refus 400 hors des 4 valeurs) à la création
  d'une dépense, au re-traitement et à l'envoi d'une page ; `rotation` dans `ExpenseDto` et
  `DocumentDto.Page`. Ancienne app : n'envoie rien → 0 (inchangé). Déployer le serveur d'abord.
- App : `Rotation` (enum, `scan/domain`) ; champ sur `Expense` et `ScannedPage` ; SQLite : colonne
  `rotation INTEGER NOT NULL DEFAULT 0` sur `expense` et `document_page` (migration) ;
  `DocumentScanner.render(…, rotation)`.

## Hors-ligne / synchro
Tout le parcours est local. La rotation voyage comme le filtre et les coins (envoi, re-traitement,
`/changes`), avec les mêmes règles de fusion.

## Domaines et couches
- `receipt/imaging` (serveur) : `Rotation`, rotation dans `OpenCvImageProcessor`.
- `expense`, `document` (serveur) : champ, DTO, paramètres d'API.
- `scan/domain` : `Rotation`, `ScanMode` (ticket, document), `ScanSession` (pages en cours, immuable).
- `scan/data` : rotation dans `DocumentScanner.render`.
- `scan/ui` : `CameraScreen` (carrousel, pile, plus de revue par prise), `ReviewScreen` (nouveau),
  `capture.dart` (point d'entrée unique `scan(context, mode)`). `AdjustScreen` reste pour réajuster
  une dépense ou une page existante (avec Pivoter).
- `expense`, `document` (app) : champ, persistance, API, synchro ; retrait des boutons flottants.
- `shell` : bouton central, bascule d'onglet après enregistrement.

## Plan (une phase = un ou plusieurs commits, TDD)
1. Rotation serveur : `Rotation`, traitement OpenCV, dépenses (création, re-traitement, DTO), pages de documents.
2. Rotation app : modèle, SQLite, API, synchro, rendu sur l'appareil, Pivoter dans `AdjustScreen`.
3. `ScanSession` + `ReviewScreen`.
4. Caméra : carrousel de modes, pile, revue à la fin ; point d'entrée `scan(context, mode)`.
5. Bouton central dans `MainShell`, retrait des boutons flottants.

## Plan de tests (ordre TDD)
1. `Rotation` (serveur) : degrés ↔ valeur, refus de 45. `OpenCvImageProcessor` : 90° échange largeur et hauteur.
2. Dépense : création avec rotation, re-traitement qui la change, `ExpenseDto.rotation` ; 400 sur 45.
3. Page de document : rotation enregistrée et rendue dans `DocumentDto`.
4. App : `Rotation.next()` ; `Expense`/`ScannedPage` (copie, JSON) ; migration SQLite qui garde les
   données ; API qui envoie `rotation` ; synchro qui la reçoit ; `render` pivoté.
5. `ScanSession` : ajoute, refuse une 2ᵉ page en Ticket, retire, remplace.
6. `ReviewScreen` : « 1 / 3 », Supprimer, Pivoter, Filtres, pas d'Ajouter en Ticket, Enregistrer.
7. `CameraScreen` : carrousel, pile + compteur, mode imposé sans carrousel.
8. `MainShell` : bouton central dans le mode de l'onglet, onglet Dépenses après un ticket.

## Alternatives écartées
- Rotation par l'ordre des coins : le serveur les retrie, la rotation serait perdue.
- Revue après chaque prise : plus lent pour un document long (choix de l'utilisateur).
- Ouverture de l'app sur la caméra : l'utilisateur garde la liste.

## Choix de l'utilisateur (24/11/2026)
Bouton central, carrousel, revue avec filtres en vignettes, pile ; Pivoter maintenant (de bout en
bout) ; revue à la fin en mode Document ; l'app s'ouvre toujours sur la liste.
