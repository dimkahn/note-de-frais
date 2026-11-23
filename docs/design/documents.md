# Documents multi-pages et export PDF / photos

## Besoin
En plus des notes de frais (un ticket = une dépense), l'application scanne des **documents** de
plusieurs pages (contrat, attestation, facture longue…). Un document comme un justificatif de dépense
s'**exporte en PDF** (toutes les pages) **ou en photos** (une image recadrée par page), via le menu
de partage du téléphone (e-mail, messagerie, Drive, « Enregistrer dans Fichiers »…).

Critères d'acceptation
- Étant donné l'onglet Documents, quand je scanne plusieurs pages à la suite puis « Terminer », alors un
  document est créé avec ces pages dans l'ordre de prise.
- Je peux ajouter des pages à un document existant, en supprimer une, le renommer, le supprimer.
- Depuis un document ou une dépense, « Exporter en PDF » produit un PDF d'une page par image ;
  « Exporter les photos » partage les images recadrées (JPEG).
- Tout fonctionne hors-ligne et sans serveur.

## Invariants touchés
- Original intact : chaque page conserve sa photo brute (écriture unique) ; recadrage/filtre = copie.
- UUID client : document et pages identifiés par des UUID générés sur l'appareil.
- Suppression logique pour le document (`deleted`) ; une page retirée l'est de la liste du document,
  ses fichiers restent sur l'appareil (pas de suppression physique d'original).
- `userEdited` : non concerné (les documents ne sont pas analysés).

## Modèle (app uniquement)
- `ScannedPage` : `id`, `originalPath`, `processedPath`, `corners`, `filter`.
- `ScannedDocument` : `id`, `title`, `createdAt`, `updatedAt`, `pages` (ordonnées), `deleted`.
- SQLite v4 : tables `document` et `document_page (document_id, position, …)`.
- Fichiers : `<support>/documents/<pageId>/original.<ext>` et `processed.jpg` (même `FileStore`).

## API / synchro
Aucune : les documents restent sur l'appareil (le serveur sert à l'analyse des dépenses).
Évolution possible : synchroniser les documents comme les dépenses.

## Couches
- `domain/document.dart` : modèles immuables, ajout/retrait de page, renommage.
- `data/local_store.dart` : persistance des documents (migration v4).
- `data/document_repository.dart` : point d'entrée de l'UI (création, pages, suppression).
- `data/export_service.dart` : construction du PDF (`pdf`) + frontière `FileSharer` (impl. `share_plus`).
- `scan/camera_screen.dart` : mode multi-pages (la caméra reste ouverte, compteur, « Terminer »).
- `ui/` : onglets Dépenses / Documents, liste et fiche document, actions d'export.

## Plan de tests
1. Domaine : ajout de pages dans l'ordre, retrait, renommage, titre par défaut.
2. LocalStore : aller-retour d'un document et de ses pages ordonnées ; migration v3 → v4.
3. DocumentRepository : création avec pages (originaux copiés), ajout, retrait, suppression logique.
4. ExportService : PDF valide d'autant de pages que d'images ; partage des photos (faux `FileSharer`).
5. Widgets : onglet Documents (liste, état vide), fiche document (pages, menu d'export).

## Alternatives écartées
- Pages multiples dans une dépense : une dépense reste un ticket ; un document n'est pas une dépense.
- Enregistrer directement dans Téléchargements : permissions variables selon Android/iOS ; le menu de
  partage couvre ce cas (« Enregistrer dans Fichiers ») et tous les autres.
