# `shared` (app, transverse)

Utilisé par plusieurs domaines ; ne contient pas de règle métier propre à un domaine.

- `data/` : `LocalStore` (SQLite, source de vérité, migrations de schéma pour toutes les tables),
  `FileStore` (`<racine>/<id>/original.<ext>` en écriture unique + `processed.jpg`), `ServerClient`
  (`OfflineException` → opération rejouée plus tard, `ApiException`, `QuotaExceededException`,
  `UnauthorizedException`), `ServerConfig` (adresses par
  type de build, `--dart-define=API_URL`), `image_types`.
- `ui/` : `theme.dart` (identité visuelle), `format.dart` (dates, montants sans `double`, tailles).

Ajouter ici seulement ce qui sert à au moins deux domaines ; sinon, le mettre dans le domaine.

Tests : `test/shared/**`.
