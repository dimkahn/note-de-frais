# Note de frais

Application de notes de frais :
- `server/` : API Java 25 / Spring Boot 4 (Maven). Recadrage auto + filtres de netteté (OpenCV),
  extraction des informations par Claude, stockage des justificatifs.
- `app/` : application Flutter, hors-ligne d'abord (SQLite local + synchronisation serveur).

## Invariants métier (ne jamais casser)
- **L'original d'un justificatif n'est jamais modifié ni supprimé** : toute transformation produit un nouveau fichier.
- Les identifiants de dépense sont des UUID générés par le client (synchronisation idempotente).
- Une correction manuelle (`userEdited`) n'est jamais écrasée par une ré-extraction.
- Les suppressions sont logiques (`deleted`) pour se propager aux autres appareils.

## Commandes
- Serveur, tests : `cd server && mvn -q test`
- Serveur, lancement : `cd server && ANTHROPIC_API_KEY=... mvn spring-boot:run`
- App, tests : `cd app && flutter test`
- App, analyse : `cd app && flutter analyze`

## Façon de travailler
- TDD obligatoire pour tout comportement : voir `.claude/rules/tdd.md` et le skill `/tdd`.
- Refactoring uniquement sous tests verts : `.claude/rules/refactoring.md`, skill `/refactor`.
- Conception avant une fonctionnalité non triviale : skill `/design-feature`.
- Relecture avant de considérer une tâche finie : skill `/review` (agent `code-reviewer`).
- Règles spécifiques : `.claude/rules/java-spring.md` (server), `.claude/rules/flutter.md` (app),
  `.claude/rules/design.md` (conception, toutes zones).
