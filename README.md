# Notes de frais

Scannez un justificatif comme avec une application de scan : **contour détecté en direct**,
**capture automatique** quand le cadrage est stable, **ajustement des 4 coins** avec loupe, **aperçu des
filtres** de netteté — le tout sur l'appareil, hors-ligne. Puis, si un serveur est configuré, **Claude en
extrait les informations** (commerçant, type, date, montant TTC, TVA, devise, lieu, moyen de paiement).
Les dépenses se filtrent et se regroupent par type, lieu, mois, commerçant ou moyen de paiement.

- **Le serveur est optionnel** : sans lui, l'application fonctionne entièrement sur l'appareil (scan,
  recadrage, filtres, saisie, recherche). Le texte du ticket est lu sur le téléphone (OCR Google ML Kit,
  hors-ligne) pour **pré-remplir** montant TTC, TVA, date, devise et commerçant, signalés « À vérifier » ;
  seule l'analyse complète par Claude (type de dépense, lieu, moyen de paiement…) manque. Configurer un serveur plus tard envoie et analyse les justificatifs déjà enregistrés,
  sans écraser les corrections manuelles.
- **Hors-ligne d'abord** : l'app enregistre tout localement (SQLite + fichiers), puis synchronise avec le serveur.
- **Originaux toujours conservés** (la photo brute pleine définition), sur l'appareil et sur le serveur ;
  ils ne sont jamais modifiés. Le recadrage et les filtres produisent une copie (`processed.jpg`) ; le cadrage
  et le filtre restent réajustables à tout moment depuis la fiche de la dépense.

## Sommaire

1. [Architecture](#architecture)
2. [Prérequis](#prérequis)
3. [Développement : serveur](#développement--serveur)
4. [Développement : application](#développement--application)
5. [Exécution sur un téléphone](#exécution-sur-un-téléphone)
6. [Build de production](#build-de-production)
7. [API du serveur](#api-du-serveur)
8. [Tests](#tests)
9. [Façon de travailler (Claude Code)](#façon-de-travailler-claude-code)

---

## Architecture

```
app/      Application Flutter (Android, iOS, desktop) — domain / data / scan / ui
server/   API Java 25, Spring Boot 4 — expense / imaging (OpenCV) / extraction (Claude) / storage / web
docs/     Documents de conception (docs/design/*.md)
.claude/  Règles, skills, agents et hooks Claude Code du projet
```

### Vue d'ensemble

```
 ┌──────────────────────────── Téléphone ────────────────────────────┐
 │ Caméra ─► détection du contour en direct (OpenCV, isolate)        │
 │        ─► photo brute = ORIGINAL (copié, jamais modifié)          │
 │        ─► recadrage + filtre sur l'appareil ─► processed.jpg      │
 │        ─► OCR ML Kit + règles ─► pré-remplissage « À vérifier »   │
 │                                                                   │
 │ SQLite (dépenses, état de synchro) + fichiers (justificatifs)     │
 │        │  file d'attente rejouable : pendingUpload / Update /     │
 │        │  Reprocess / Delete                                      │
 └────────┼──────────────────────────────────────────────────────────┘
          │ HTTP(S), en-tête X-Api-Token          (optionnel)
 ┌────────▼────────────────────── Serveur ───────────────────────────┐
 │ web (REST) ─► expense (service, file de traitement asynchrone)    │
 │                 ├─► imaging : même découpe en pleine définition   │
 │                 ├─► extraction : Claude (vision + sortie JSON)    │
 │                 └─► storage : <id>/original.<ext>, processed.jpg  │
 │ Base : H2 fichier (défaut) ou PostgreSQL                          │
 └───────────────────────────────────────────────────────────────────┘
```

### Application (`app/lib/`)

| Couche | Rôle | Exemples |
|---|---|---|
| `domain/` | Modèles immuables et règles pures, sans Flutter ni E/S | `Expense`, `Money`, `Quad` (contour normalisé), `StabilityTracker` (déclenchement auto), `ReceiptParser` (montants, TVA, date… dans le texte lu), `ExpenseQuery` |
| `data/` | Persistance et réseau | `LocalStore` (SQLite), `FileStore` (justificatifs), `ExpenseApi` (HTTP), `SyncService`, `ExpenseRepository` (point d'entrée de l'UI) |
| `scan/` | Scanner et lecture sur l'appareil | `DocumentScanner` (OpenCV : détection, redressement, filtres), `MlKitReceiptTextReader` (OCR), `CameraScreen`, `AdjustScreen`, `CornerEditor` |
| `ui/` | Écrans et widgets (Material 3, libellés en français) | `HomeScreen`, `ExpenseDetailScreen`, `SettingsScreen` |

Principes :
- **Toute action écrit d'abord en local**, puis déclenche une synchronisation. Sans serveur configuré,
  la synchronisation est simplement inactive ; les changements restent en file et partent dès qu'un
  serveur est renseigné dans les Réglages.
- Les identifiants de dépense sont des **UUID générés par l'appareil** : la synchronisation est idempotente.
- Synchronisation : on pousse d'abord les changements locaux, puis on tire les changements serveur
  (`/changes?since=`). Une dépense modifiée localement et non envoyée n'est jamais écrasée.
- Suppressions **logiques** (`deleted`), pour se propager aux autres appareils.
- Une correction manuelle (`userEdited`) n'est jamais écrasée par une nouvelle extraction.
- **Lecture sur l'appareil** : après un scan, l'OCR lit l'image recadrée et ne complète que les champs
  vides (`prefilled`). Ce pré-remplissage reste propre à l'appareil : il n'est jamais envoyé comme une
  correction manuelle ; l'analyse du serveur le remplace une fois terminée, une correction de l'utilisateur
  le valide. Conception : `docs/design/lecture-locale.md`.
- Détection en direct : chaque image du flux est réduite à 400 px puis analysée dans un isolate ;
  la capture se déclenche quand le contour reste stable ~1,2 s (une perte brève de détection est tolérée).

### Serveur (`server/src/main/java/fr/notedefrais/`)

| Paquet | Rôle |
|---|---|
| `web` | Contrôleur REST, DTO + Bean Validation, traduction des erreurs (`ApiExceptionHandler`) |
| `expense` | Domaine : `Expense`, `ExpenseService`, file de traitement asynchrone |
| `imaging` | `ImageProcessor` → `OpenCvImageProcessor` (recadrage, filtres de netteté) |
| `extraction` | `ReceiptExtractor` → `ClaudeReceiptExtractor` (ou `DisabledReceiptExtractor`) |
| `storage` | `FileStorage` → `LocalFileStorage` (l'original ne peut pas être écrasé) |
| `config` | Propriétés, filtre de jeton d'API, câblage des intégrations |

Le domaine ne connaît ni HTTP, ni OpenCV, ni le SDK Anthropic : les intégrations sont derrière des
interfaces définies côté métier. Le contour choisi sur l'appareil (`corners`) est envoyé au serveur, qui
produit la même découpe en pleine définition (algorithme identique en Dart et en Java, à garder aligné).
Conception détaillée du scanner : `docs/design/scanner.md`.

---

## Prérequis

| Outil | Version | Pour |
|---|---|---|
| Flutter SDK | Dart ≥ 3.13 | application |
| Android SDK + `adb` | API récente, JDK 17 | Android |
| Xcode + CocoaPods | macOS uniquement | iOS |
| JDK | 25 | serveur |
| Maven | 3.9+ | serveur |
| Clé API Anthropic | — | extraction automatique (serveur) |

`flutter doctor` vérifie l'installation côté application.

---

## Développement : serveur

```bash
cd server
export ANTHROPIC_API_KEY=sk-ant-...   # ou `ant auth login` (profil lu automatiquement)
export NDF_API_TOKEN=un-jeton-long     # recommandé dès que le serveur est accessible sur le réseau
mvn spring-boot:run                    # écoute sur http://0.0.0.0:8080
```

| Variable | Défaut | Rôle |
|---|---|---|
| `PORT` | `8080` | Port HTTP |
| `NDF_STORAGE_DIR` | `./storage` | Justificatifs : `<id>/original.<ext>` et `<id>/processed.jpg` |
| `NDF_DB_URL` / `NDF_DB_USER` / `NDF_DB_PASSWORD` | H2 fichier `./data` | Base (PostgreSQL supporté) |
| `NDF_API_TOKEN` | vide (désactivé) | Jeton exigé dans l'en-tête `X-Api-Token` |
| `NDF_CLAUDE_ENABLED` | `true` | `false` : pas d'extraction, champs à saisir |
| `NDF_CLAUDE_MODEL` | `claude-opus-5-5` | Modèle utilisé pour l'extraction |

L'extraction utilise l'API Claude (sortie structurée + vision), facturée à l'usage sur le compte de la clé.
Un refus du modèle est rejoué automatiquement sur un modèle de repli (`fallbacks: "default"`).

## Développement : application

```bash
cd app
flutter pub get
flutter run -d linux     # desktop : choix d'une image au lieu de la caméra
```

Puis, si un serveur est disponible : **Réglages → Adresse du serveur** (ex. `http://192.168.1.10:8080`)
et jeton. Laisser l'adresse vide pour utiliser l'application sans serveur.

---

## Exécution sur un téléphone

### Android

1. Sur le téléphone : **Paramètres → À propos → appuyer 7 fois sur « Numéro de build »**, puis
   **Options pour les développeurs → Débogage USB** (sur Xiaomi/HyperOS, activer aussi
   « Installer via USB » et « Débogage USB (paramètres de sécurité) »).
2. Brancher le téléphone, accepter l'empreinte RSA de l'ordinateur, puis vérifier :
   ```bash
   flutter devices          # le téléphone doit apparaître, ex. « 23078PND5G (mobile) »
   ```
3. Lancer :
   ```bash
   cd app
   flutter run -d <id>             # debug : rechargement à chaud (touche r), mais lent
   flutter run -d <id> --profile   # performances réalistes (à utiliser pour juger la détection en direct)
   ```
4. Journaux : `flutter logs -d <id>` ou `adb logcat -s flutter`.

Le mode debug est nettement plus lent (code non compilé AOT) : la détection du contour en direct
doit être évaluée en `--profile` ou `--release`.

### Joindre le serveur de développement depuis le téléphone

- **Par USB (le plus simple)** :
  ```bash
  adb reverse tcp:8080 tcp:8080
  ```
  puis, dans l'application, adresse du serveur `http://localhost:8080`. À refaire à chaque branchement.
- **Par Wi-Fi** : téléphone et ordinateur sur le même réseau ; adresse `http://<IP-de-l-ordinateur>:8080`
  (`ip -4 addr` pour la trouver) ; autoriser le port 8080 dans le pare-feu (`sudo ufw allow 8080/tcp`).

### iOS (macOS requis)

```bash
cd app && open ios/Runner.xcworkspace
```
Dans Xcode : **Runner → Signing & Capabilities → Team** (compte Apple, même gratuit), puis brancher
l'iPhone, activer le **mode développeur** (Réglages → Confidentialité et sécurité) et :
```bash
flutter run -d <id-de-l-iphone> --profile
```

---

## Build de production

### Version

Incrémenter `version:` dans `app/pubspec.yaml` (`1.0.0+1` = nom `1.0.0`, code de build `1`) à chaque
publication : les stores refusent un code de build déjà utilisé.

### Android

1. **Créer la clé de signature** (une seule fois ; la conserver précieusement : sans elle, plus de mise à jour possible) :
   ```bash
   keytool -genkey -v -keystore ~/note-de-frais-release.jks \
     -keyalg RSA -keysize 4096 -validity 10000 -alias note-de-frais
   ```
2. **Créer `app/android/key.properties`** (ignoré par git — ne jamais le commiter) :
   ```properties
   storeFile=/home/<vous>/note-de-frais-release.jks
   storePassword=...
   keyAlias=note-de-frais
   keyPassword=...
   ```
   Sans ce fichier, le build `release` est signé avec la clé de debug (utilisable en local, pas publiable).
3. **Construire** :
   ```bash
   cd app
   flutter build appbundle --release            # Google Play : build/app/outputs/bundle/release/app-release.aab
   flutter build apk --release --split-per-abi  # installation directe : build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
   ```
4. Avant publication : remplacer l'identifiant `fr.notedefrais.note_de_frais`
   (`android/app/build.gradle.kts`) si besoin, et, si le serveur de production est en HTTPS, retirer
   `android:usesCleartextTraffic="true"` de `AndroidManifest.xml` (il n'autorise le HTTP en clair que
   pour le développement).

### iOS

```bash
cd app
flutter build ipa --release     # build/ios/ipa/*.ipa, à envoyer avec Transporter ou Xcode → Organizer
```
Prérequis : compte Apple Developer payant, identifiant `fr.notedefrais.noteDeFrais` enregistré, équipe
de signature choisie dans Xcode.

### Serveur

```bash
cd server
mvn -q package                  # tests compris ; produit target/note-de-frais-server-0.1.0.jar
java -jar target/note-de-frais-server-0.1.0.jar
```

Le JAR est autonome (OpenCV `org.openpnp` embarque ses bibliothèques natives Linux/macOS/Windows).
Configuration de production recommandée :

```bash
export ANTHROPIC_API_KEY=...                   # depuis un gestionnaire de secrets, jamais dans le code
export NDF_API_TOKEN=$(openssl rand -hex 32)   # obligatoire dès que le serveur est exposé
export NDF_DB_URL=jdbc:postgresql://db/ndf NDF_DB_USER=ndf NDF_DB_PASSWORD=...
export NDF_STORAGE_DIR=/var/lib/note-de-frais/storage   # volume persistant et sauvegardé
java -jar note-de-frais-server-0.1.0.jar
```

- Exposer le serveur **uniquement en HTTPS**, derrière un proxy inverse (Caddy, Nginx, Traefik) qui
  termine TLS et relaie vers le port 8080. Prévoir une taille de requête ≥ 26 Mo (justificatifs).
- **Sauvegarder** la base *et* `NDF_STORAGE_DIR` : les originaux n'existent que là et sur les appareils.
- Le schéma est mis à jour automatiquement au démarrage (`ddl-auto: update`).

---

## API du serveur

| Méthode | Chemin | |
|---|---|---|
| `POST` | `/api/expenses` (multipart `file`, `id`?, `filter`?, `corners`?) | Envoi d'un justificatif → `202`, traitement en tâche de fond |
| `GET` | `/api/expenses?category&city&country&merchant&from&to&q` | Recherche |
| `GET` | `/api/expenses/summary?groupBy=CATEGORY\|CITY\|COUNTRY\|MERCHANT\|MONTH\|PAYMENT_METHOD` | Totaux par devise |
| `GET` | `/api/expenses/changes?since=<instant>` | Synchronisation (suppressions incluses) |
| `GET` / `PUT` / `DELETE` | `/api/expenses/{id}` | Lecture / correction manuelle / suppression logique |
| `POST` | `/api/expenses/{id}/reprocess?filter=&corners=` | Nouveau traitement depuis l'original |
| `GET` | `/api/expenses/{id}/original`, `/processed` | Images |

`corners` : `x1,y1,x2,y2,x3,y3,x4,y4`, coins normalisés (0..1) haut-gauche, haut-droit, bas-droit, bas-gauche.
Sans `corners`, le serveur détecte lui-même le document.

Filtres : `NONE` (recadrage seul), `ENHANCE` (CLAHE + masque flou, par défaut), `SHARPEN`, `SCAN_BW` (noir et blanc type scanner).

---

## Tests

```bash
cd server && mvn -q test        # OpenCV sur images synthétiques, faux serveur Claude, MVC, JPA, bout en bout
cd app && flutter test          # géométrie, OpenCV sur l'appareil, base locale + migration, synchro, écrans
cd app && flutter analyze       # zéro avertissement exigé
```

---

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
