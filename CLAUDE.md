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

## Domaines fonctionnels
Code découpé par domaine, puis par couche. Chaque dossier de domaine a son `CLAUDE.md` (lu quand on y
travaille) : responsabilité, invariants propres, frontières, tests.

| Domaine | Serveur `server/src/main/java/fr/notedefrais/` | App `app/lib/` |
|---|---|---|
| Comptes, sessions, offres, quotas | `account/` (+ `web/`, `google/`) | `account/` |
| Dépenses (justificatifs, synchro) | `expense/` (+ `web/`) | `expense/` |
| Documents multi-pages | `document/` (+ `web/`) | `document/` |
| Traitement d'image, lecture du ticket | `receipt/` (`imaging/`, `extraction/`) | `scan/` (caméra, recadrage, OCR) |
| Export PDF / photos | — | `export/` |
| Transverse | `storage/`, `web/` (erreurs HTTP), `config/` | `shared/`, `shell/` (navigation) |

## Commandes
- Tout (racine) : `mvn verify` — tests serveur, `flutter analyze` + `flutter test`, APK release
  (`app/build/app/outputs/flutter-apk/app-release.apk`, signé avec la clé debug sans `android/key.properties`).
  Options : `-DskipFlutter` (serveur seul, sans SDK Flutter), `-DskipTests`,
  `-Dflutter.target=apk|appbundle|linux`, `-Dflutter.mode=release|profile|debug`,
  `-Dapi.url=https://…` (→ `--dart-define=API_URL=…`). `mvn clean` lance aussi `flutter clean`.
- Serveur seul : `mvn -DskipFlutter verify` ; lancement depuis la racine :
  `ANTHROPIC_API_KEY=... mvn -pl server spring-boot:run`
- Serveur, tests : `cd server && mvn -q test`
- Serveur, lancement : `cd server && ANTHROPIC_API_KEY=... mvn spring-boot:run`
- App, tests : `cd app && flutter test`
- App, analyse : `cd app && flutter analyze`
- App contre le serveur local (téléphone en USB) : `adb reverse tcp:8080 tcp:8080 && cd app && flutter run`
  (debug/profile → `http://localhost:8080`, release → `https://api.notedefrais.fr` ; adresses dans
  `app/lib/shared/data/server_config.dart`, surchargeables par `--dart-define=API_URL=...` ou Compte › Avancé)

## Façon de travailler
- TDD obligatoire pour tout comportement : voir `.claude/rules/tdd.md` et le skill `/tdd`.
- Refactoring uniquement sous tests verts : `.claude/rules/refactoring.md`, skill `/refactor`.
- Conception avant une fonctionnalité non triviale : skill `/design-feature`.
- Relecture avant de considérer une tâche finie : skill `/review` (agent `code-reviewer`).
- Règles spécifiques : `.claude/rules/java-spring.md` (server), `.claude/rules/flutter.md` (app),
  `.claude/rules/design.md` (conception, toutes zones).
