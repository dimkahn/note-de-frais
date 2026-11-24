# `web` (serveur, transverse) — frontière HTTP commune

Les contrôleurs et DTO vivent dans `<domaine>/web/`. Ici seulement :
- `ApiExceptionHandler` : **seul** endroit qui traduit les exceptions métier en réponses HTTP (RFC 9457).
  Toute nouvelle exception métier y reçoit son code.
- `ImageUploads` : validation des images envoyées (type, JPEG, coins), partagée par `expense/web` et `document/web`.
- `BadRequestException`, `UnsupportedImageTypeException`.
