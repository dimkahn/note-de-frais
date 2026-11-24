# Domaine `document` (serveur) — documents multi-pages

Contrepartie app : `app/lib/document/`. Conception : `docs/design/documents.md`,
`docs/design/comptes-et-offres.md` (phase 4).

- `Document` (titre, pages ordonnées, `deleted`), `DocumentPage` (original + rendu calculé sur l'appareil),
  `DocumentService` (avec son propre `FileStorage`), `DocumentContent` = document + pages visibles.
- `document/web/` : `/api/documents/**` ; l'appareil envoie l'original **et** le rendu de chaque page.

Invariants propres
- Aucune analyse IA ni traitement d'image serveur : le rendu vient de l'appareil.
- UUID client pour le document et chaque page ; renvoi idempotent.
- Page retirée = retirée de la liste, fichiers conservés ; document supprimé = `deleted` logique.
- Les pages comptent dans le quota (`StorageUsage` exposé à `account`) ; un ajout au-delà → 403.
- Document ou page d'un autre compte : indiscernable d'un inexistant (404).

Tests : `DocumentServiceTest`, `document/web/DocumentControllerTest`, `DocumentFlowTest`.
