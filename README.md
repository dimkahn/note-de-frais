# Notes de frais

Photographiez un justificatif : il est **recadré automatiquement**, **amélioré** (netteté / contraste),
puis **Claude en extrait les informations** (commerçant, type, date, montant TTC, TVA, devise, lieu,
moyen de paiement). Les dépenses se filtrent et se regroupent par type, lieu, mois, commerçant ou moyen de paiement.

- **Hors-ligne d'abord** : l'app enregistre tout localement (SQLite + fichiers), puis synchronise avec le serveur.
- **Originaux toujours conservés**, sur l'appareil et sur le serveur ; ils ne sont jamais modifiés.
  Le recadrage et les filtres produisent une copie (`processed.jpg`), qu'on peut régénérer avec un autre filtre.

```
app/      Flutter (Android, iOS, desktop) — domain / data / ui
server/   Java 25, Spring Boot 4 — expense / imaging (OpenCV) / extraction (Claude) / storage / web
.claude/  règles, skills, agents et hooks Claude Code du projet
```

## Serveur

```bash
cd server
export ANTHROPIC_API_KEY=sk-ant-...   # ou `ant auth login` (profil lu automatiquement)
export NDF_API_TOKEN=un-jeton-long     # recommandé dès que le serveur est accessible sur le réseau
mvn spring-boot:run
```

| Variable | Défaut | Rôle |
|---|---|---|
| `NDF_STORAGE_DIR` | `./storage` | Justificatifs : `<id>/original.<ext>` et `<id>/processed.jpg` |
| `NDF_DB_URL` / `NDF_DB_USER` / `NDF_DB_PASSWORD` | H2 fichier `./data` | Base (PostgreSQL supporté) |
| `NDF_API_TOKEN` | vide (désactivé) | Jeton exigé dans l'en-tête `X-Api-Token` |
| `NDF_CLAUDE_ENABLED` | `true` | `false` : pas d'extraction, champs à saisir |
| `NDF_CLAUDE_MODEL` | `claude-opus-5-5` | Modèle utilisé pour l'extraction |

L'extraction utilise l'API Claude (sortie structurée + vision), facturée à l'usage sur le compte de la clé.
Un refus du modèle est rejoué automatiquement sur un modèle de repli (`fallbacks: "default"`).

### API

| Méthode | Chemin | |
|---|---|---|
| `POST` | `/api/expenses` (multipart `file`, `id`?, `filter`?) | Envoi d'un justificatif → `202`, traitement en tâche de fond |
| `GET` | `/api/expenses?category&city&country&merchant&from&to&q` | Recherche |
| `GET` | `/api/expenses/summary?groupBy=CATEGORY\|CITY\|COUNTRY\|MERCHANT\|MONTH\|PAYMENT_METHOD` | Totaux par devise |
| `GET` | `/api/expenses/changes?since=<instant>` | Synchronisation (suppressions incluses) |
| `GET` / `PUT` / `DELETE` | `/api/expenses/{id}` | Lecture / correction manuelle / suppression logique |
| `POST` | `/api/expenses/{id}/reprocess?filter=` | Nouveau traitement depuis l'original |
| `GET` | `/api/expenses/{id}/original`, `/processed` | Images |

Filtres : `NONE` (recadrage seul), `ENHANCE` (CLAHE + masque flou, par défaut), `SHARPEN`, `SCAN_BW` (noir et blanc type scanner).

## Application

```bash
cd app
flutter run            # puis Réglages → adresse du serveur (ex. http://192.168.1.10:8080) et jeton
```

## Tests

```bash
cd server && mvn test       # 52 tests : OpenCV sur images synthétiques, faux serveur Claude, MVC, JPA, bout en bout
cd app && flutter test      # domaine, base locale, synchro (faux serveur HTTP), écrans
```

## Façon de travailler (Claude Code)

`CLAUDE.md` et `.claude/` imposent TDD, refactoring sous tests verts et conception en couches :

- **Règles** `.claude/rules/` : `tdd`, `refactoring`, `design`, `java-spring` (server/**), `flutter` (app/**).
- **Skills** : `/tdd`, `/refactor`, `/design-feature`, `/review`.
- **Agents** : `code-reviewer` (lecture seule), `test-writer` (phase rouge), `refactorer`, `architect`.
- **Hooks** (`.claude/settings.json`) :
  - `guard.sh` bloque toute suppression/modification des justificatifs stockés, des fichiers de secrets, et les `push --force` / `reset --hard` ;
  - `format.sh` formate les fichiers Dart modifiés ;
  - `tdd-guard.sh` signale tout code de production sans test associé ;
  - `run-tests.sh` relance les tests concernés en fin de tâche et empêche de conclure tant qu'ils échouent.
