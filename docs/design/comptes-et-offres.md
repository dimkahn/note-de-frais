# Comptes et offres (Gratuit 100 Mo / Premium 1 Go + analyse IA)

Choix validés le 2026-11-23 : connexion e-mail + mot de passe **et** Google ; pas de paiement pour
l'instant (offre attribuée à la main) ; le quota compte **tout ce qui est stocké en ligne**
(justificatifs et documents, originaux compris) ; l'app reste **utilisable sans compte** (mode local).

## Besoin (critères d'acceptation)

- Sans compte, tout fonctionne en local comme aujourd'hui (scan, lecture sur l'appareil, exports).
- Réglages devient la page **Compte** : connexion / inscription, ou état du compte connecté.
- Connecté, mes dépenses (puis mes documents) sont sauvegardées et synchronisées sur le serveur,
  pour **mon compte uniquement**.
- Gratuit : au-delà de 100 Mo (originaux + rendus), l'envoi est refusé avec un message clair ;
  l'analyse IA n'est pas lancée. Premium : 1 Go et analyse IA par le serveur.
- Premium est attribué manuellement (endpoint d'administration) ; paiement plus tard
  (Google Play Billing obligatoire pour vendre dans l'app Android).

## Invariants

Originaux jamais modifiés ; UUID générés par le client (l'envoi des données locales vers un
nouveau compte est rejouable) ; `userEdited` ; suppressions logiques. **Nouveau** : un compte ne
voit ni ne modifie jamais les données d'un autre — identifiant étranger → 404.

## Modèle serveur (paquet `account`)

- `Account` : id UUID, e-mail unique (normalisé en minuscules), hash du mot de passe (nullable,
  BCrypt via `spring-security-crypto`), identifiant Google `sub` (nullable), `Plan`, date de création.
- `Plan` : FREE / PREMIUM ; quota en octets et « analyse IA incluse » lus dans `application.yml`.
- `Session` : jeton aléatoire (256 bits) rendu à l'app ; seul son hash SHA-256 est stocké, avec
  une expiration (configurable) → la déconnexion révoque vraiment.
- `Expense` : + `ownerId`, + `sizeBytes` (original + rendu). Données existantes sans propriétaire :
  données de développement, rattachables à un compte par une commande ponctuelle.
- Le jeton partagé actuel (`X-Api-Token`, `app.api-token`) devient le jeton **d'administration**.

## API (en-tête `Authorization: Bearer <jeton>`)

| Endpoint | Résultat |
|---|---|
| `POST /api/auth/register` `{email, password}` | 201 `{token, account}` · 409 e-mail pris · 400 mot de passe < 10 caractères ou e-mail invalide |
| `POST /api/auth/login` `{email, password}` | 200 `{token, account}` · 401 (message identique e-mail inconnu / mauvais mot de passe) |
| `POST /api/auth/google` `{idToken}` | 200 ; compte créé, ou lié si l'e-mail Google est vérifié et existe déjà |
| `POST /api/auth/logout` | 204 |
| `GET /api/account` | `{email, plan, usedBytes, quotaBytes, aiAnalysis}` |
| `PUT /api/admin/accounts/{email}/plan` `{plan}` | jeton d'administration (`X-Api-Token`) |
| `/api/expenses/**` | inchangés, filtrés par compte ; 401 sans session valide |
| envoi au-delà du quota | 403, corps `{code: "QUOTA_EXCEEDED", usedBytes, quotaBytes}` |

Analyse IA : en Gratuit, le justificatif est stocké sans appel à Claude (statut `NOT_INCLUDED`) ;
l'app garde les valeurs lues sur l'appareil.

## App

- Réglages → **Compte**. Déconnecté : « Se connecter / Créer un compte » (e-mail + mot de passe,
  « Continuer avec Google »), les deux offres côte à côte, rappel « l'app fonctionne sans compte ».
  Connecté : e-mail, offre, barre d'usage (« 42 Mo sur 100 Mo »), « Passer à Premium »
  (bientôt disponible), « Se déconnecter ». Adresse du serveur dans une section « Avancé ».
- Jeton dans le stockage sécurisé (`flutter_secure_storage`), envoyé en `Authorization: Bearer`.
- À la connexion, les dépenses locales sont envoyées vers le compte ; quota dépassé → elles restent
  sur l'appareil avec un message. 401 → retour à l'état déconnecté, données locales conservées.

## Phases (un commit par phase au moins, TDD)

1. **Comptes e-mail** : serveur (inscription, connexion, déconnexion, sessions, `GET /api/account`,
   isolation des dépenses par compte) + page Compte de l'app (e-mail / mot de passe), jeton stocké,
   synchro authentifiée.
2. **Offres et quotas** : comptage des tailles, refus au-delà du quota, IA réservée à Premium
   (`NOT_INCLUDED`), barre d'usage, endpoint d'administration du plan.
3. **Connexion Google** : vérification du jeton Google côté serveur (identifiant client OAuth en
   configuration), `google_sign_in` côté app. Nécessite un projet Google Cloud et les identifiants
   OAuth (SHA-1 de l'app) : à créer par l'utilisateur.
1b. **Connexion par empreinte** (choix du 2026-11-23 : reconnexion sans mot de passe, pas de
   verrouillage de l'app). Serveur : `POST /api/auth/devices` (connecté) émet une **clé d'appareil**
   longue durée (256 bits, seul le hash SHA-256 stocké, révocable, libellé de l'appareil) ;
   `POST /api/auth/device-login {deviceKey}` → nouvelle session (401 si clé inconnue ou révoquée) ;
   `DELETE /api/auth/devices/current` (connecté, clé dans le corps) la révoque. App : après connexion,
   « Activer la connexion par empreinte » sur la page Compte ; la clé est en stockage sécurisé et
   n'est lue qu'après une authentification biométrique réussie (`local_auth`, biométrie seule,
   derrière une interface doublée dans les tests) ; déconnecté avec une clé enregistrée →
   bouton « Se connecter avec l'empreinte » à côté du formulaire (le mot de passe reste possible) ;
   « Désactiver l'empreinte » révoque la clé et l'efface. La déconnexion conserve la clé. 401 au
   device-login → clé effacée, retour au formulaire.
4. **Documents synchronisés sur le serveur** (comptent dans le quota).
5. **Paiement** : plus tard.

## Décisions prises en phase 1

- Sans `NDF_API_TOKEN` configuré, `/api/admin/**` est **fermé** (sinon n'importe qui s'attribuerait Premium).
- À chaque connexion, la date de dernière synchro est remise à zéro (récupère tout le compte,
  même après un changement de compte sur l'appareil).
- Mot de passe : 10 caractères minimum, 72 octets maximum (limite BCrypt) → 400 au-delà.
- Restent ouverts : rattachement des dépenses d'avant les comptes (sans propriétaire, invisibles).
- Adresse du serveur par type de build (résolu après la phase 1b) : debug/profile →
  `http://localhost:8080` (téléphone relié au PC par `adb reverse tcp:8080 tcp:8080`), release →
  `https://api.notedefrais.fr` (provisoire). Constantes dans `app/lib/data/server_config.dart`,
  surchargeables au build par `--dart-define=API_URL=...` ; le champ de « Avancé » reste une
  surcharge facultative (vide = adresse du build, l'adresse effective est affichée). Android : http
  en clair autorisé seulement en debug et seulement vers localhost (`src/debug`, network security config).

## Décisions prises en phase 1b (connexion par empreinte)

- Révoquer une clé = supprimer sa ligne `device_key`. Révoquer la clé d'un autre compte est sans
  effet (204, ne révèle rien). Les clés n'expirent pas : seule la révocation les invalide.
- L'activation demande d'abord une empreinte reconnue (on vérifie que la biométrie fonctionne avant
  d'émettre la clé). Une session refusée (401) à l'activation déconnecte, comme ailleurs.
- La désactivation lit la clé **sans** empreinte : elle ne sert qu'à la révoquer, puis est effacée ;
  l'effacement local a lieu même si la révocation échoue (hors-ligne).
- Libellé de l'appareil envoyé au serveur : le système (`android`, `ios`…).
- « Biométrie disponible » = capteur présent **et** au moins une biométrie enregistrée, évalué au
  lancement de l'app ; sinon (desktop, émulateur, rien d'enregistré) l'option n'est pas proposée.
- iOS : `NSFaceIDUsageDescription` ajouté (Face ID compte comme biométrie).
- Changement de compte (résolu) : la clé est enregistrée avec l'e-mail du compte qui l'a activée.
  Une connexion par mot de passe (ou une inscription) à un **autre** compte efface la clé de
  l'appareil, sans la révoquer (seule une session de son compte le pourrait), et l'option
  « Activer la connexion par empreinte » est reproposée pour le nouveau compte. Une clé enregistrée
  avant ce correctif (compte inconnu) est effacée de même à la connexion par mot de passe.
- Reste ouvert : une clé non révoquée (désactivation hors-ligne, changement de compte) reste valide
  sur le serveur — une liste des appareils avec révocation dans la page Compte le réglerait.

## Décisions prises en phase 2 (offres et quotas)

- **Une suppression logique libère le quota** : l'usage d'un compte est la somme des `sizeBytes`
  de ses dépenses **non supprimées** ; les fichiers d'une dépense supprimée restent sur le disque
  (originaux jamais supprimés) mais ne comptent plus.
- `sizeBytes` = original + rendu courant. À l'envoi, seul l'original est connu : le contrôle porte
  sur `usage + taille de l'original > quota` (égalité acceptée) ; le rendu, ajouté au traitement,
  peut faire dépasser légèrement le quota — accepté. Le re-traitement remplace la taille du rendu.
- Contrôle du quota sans verrou : deux envois simultanés du même compte peuvent dépasser le quota
  d'au plus un justificatif — accepté (borné, pas de paiement en jeu).
- Le renvoi d'une dépense déjà enregistrée (même UUID) n'est jamais refusé pour quota (idempotence).
- Dépenses antérieures aux quotas (sans taille) : taille calculée depuis les fichiers au démarrage
  (requête ciblée qui n'écrit que `sizeBytes`, sans toucher au traitement en cours) ; fichiers
  illisibles → restent sans taille (non comptés), retentées au démarrage suivant.
- Offres dans `app.plans.<offre>.{quota, ai-analysis}` (`DataSize` : 100MB = 104 857 600 octets) ;
  une offre sans configuration fait échouer le démarrage. Sans IA, le rendu est produit et le statut
  est `NOT_INCLUDED` ; les champs (lus sur l'appareil ou corrigés) ne sont pas touchés, y compris au
  re-traitement. Les dépenses sans propriétaire ne sont jamais analysées.
- `PUT /api/admin/accounts/{email}/plan` répond 200 `{email, plan}` (e-mail normalisé) ; 400 sans
  offre valide. Les réponses d'inscription/connexion restent `{email, plan}` : l'app relit
  `GET /api/account` juste après la connexion pour l'usage et le quota.
- App, envoi refusé pour quota : la dépense reste en attente d'envoi sur l'appareil et est **retentée
  à la synchronisation suivante** (action de l'utilisateur, lancement, reconnexion) — le choix le plus
  simple. Pas de boucle : le rafraîchissement périodique ne concerne plus que les dépenses déjà reçues
  par le serveur. La page Compte affiche « Espace en ligne plein : N dépense(s) reste(nt) sur cet
  appareil » d'après le rapport de la dernière synchro (chaque synchro retente l'envoi, donc le
  message revient tant que la place manque). L'usage est relu après chaque synchro qui a envoyé ou
  refusé quelque chose. Reste ouvert : chaque synchro renvoie l'image entière d'une capture refusée
  (ne retenter qu'une fois de la place libérée économiserait des données mobiles).
- App, barre d'usage : Mo binaires (1 Mo = 1 048 576 octets, cohérent avec 100MB côté serveur),
  « 0,3 Mo » sous 1 Mo, Go au-delà de 1 Go ; couleur d'erreur strictement au-delà de 90 %.
- `NOT_INCLUDED` : badge calculé comme sans serveur (« À vérifier » / « À compléter ») et bandeau
  « Analyse IA incluse avec Premium » sur la fiche ; le pré-remplissage de l'appareil est conservé.

## Décisions prises en phase 3 (connexion Google)

- `POST /api/auth/google {idToken}` → 200 `{token, account}` comme la connexion. Le jeton est vérifié
  (signature, émetteur, audience = identifiant client OAuth « web », validité) par `google-api-client`
  derrière `GoogleIdentityVerifier` (paquet `account`), implémenté dans le paquet `google` ; la
  vérification (réseau : certificats de Google) a lieu **hors transaction**, dans le contrôleur.
- Sans `NDF_GOOGLE_CLIENT_ID` : **503** « Connexion Google non configurée sur ce serveur » (plutôt
  que 404 : la route existe, c'est la configuration qui manque, et l'app affiche un message clair).
  Google injoignable ou certificats illisibles → 503 aussi. Jeton invalide, expiré, mal formé ou
  destiné à une autre application → 401. Jeton de plus de 4 096 caractères → 400.
- Règles : `sub` connu → connexion (même si l'e-mail Google a changé) ; sinon e-mail **vérifié**
  par Google égal à celui d'un compte → liaison ; sinon création en Gratuit sans mot de passe.
  Refus **403** avec le motif : e-mail non vérifié (y compris pour une création, pour ne pas
  réserver l'adresse d'un tiers), ou compte déjà lié à un **autre** compte Google.
- **La liaison retire le mot de passe, les sessions et les clés d'appareil existants** du compte :
  l'inscription ne prouve pas la possession de l'e-mail, un tiers a donc pu créer le compte avant
  son titulaire ; après liaison, seul Google ouvre le compte. Conséquence : un utilisateur qui
  avait un mot de passe ne s'en sert plus (message clair au login). À rediscuter si l'on ajoute
  la vérification de l'e-mail à l'inscription.
- Un compte sans mot de passe (créé ou lié par Google) qui tente le mot de passe reçoit 401 avec
  `code: "PASSWORD_NOT_SET"` ; l'app affiche « Ce compte n'a pas de mot de passe : utilisez
  « Continuer avec Google » ». Assumé : cela révèle qu'un compte existe pour cet e-mail, comme
  déjà l'inscription (409).
- App : `google_sign_in` 7 derrière `GoogleAuth` ; annulation → rien ne change ; 401 → « Connexion
  Google refusée, réessayez. », 403 → motif du serveur, 503 → « indisponible sur ce serveur ».
  Ensuite tout se passe comme après une connexion par mot de passe (synchro, empreinte proposée,
  clé d'un autre compte effacée). `serverClientId` : `buildGoogleServerClientId` dans
  `app/lib/data/server_config.dart`, surchargeable par `--dart-define=GOOGLE_SERVER_CLIENT_ID=...` ;
  vide → bouton masqué.
- Restent ouverts : iOS non configuré (identifiant client iOS + schéma d'URL dans `Info.plist`) ;
  deux premières connexions Google simultanées pour le même compte peuvent se heurter à l'unicité
  (500, la suivante réussit) ; pas de « délier Google » ni de « définir un mot de passe ».

## Mise en place Google (pas à pas)

Rien n'est à inventer : chaque identifiant vient de la console Google Cloud.

1. **Projet** : <https://console.cloud.google.com/> → sélecteur de projet → « Nouveau projet »
   (par ex. « Note de frais »).
2. **Écran de consentement** : « API et services » → « Écran de consentement OAuth » (ou « Google
   Auth Platform » → « Branding ») : type **Externe**, nom de l'app, e-mail d'assistance et de
   contact. Portées : les portées de base (`openid`, `email`, `profile`) suffisent. Tant que l'app
   est « En test », ajouter les comptes Google autorisés dans « Utilisateurs test ».
3. **Identifiant client « Application Web »** (pour le serveur) : « Identifiants » (ou « Clients »)
   → « Créer des identifiants » → « ID client OAuth » → type **Application Web**, nom « Serveur
   note de frais », sans origine ni URI de redirection. Copier l'ID client
   (`….apps.googleusercontent.com`) ; le code secret n'est **pas** utilisé.
4. **Identifiant client « Android »** (pour l'app) : même menu → type **Android**, nom du paquet
   `fr.notedefrais.note_de_frais`, empreinte **SHA-1** du certificat de signature. Pour le
   certificat debug :

   ```sh
   keytool -list -v -alias androiddebugkey -keystore ~/.android/debug.keystore \
     -storepass android -keypass android
   # ou, depuis app/android :
   ./gradlew signingReport   # ligne « SHA1 » de la variante debug
   ```

   Rien à copier dans l'app depuis cet identifiant : Google reconnaît l'app par son paquet et son
   SHA-1. Créer un second identifiant Android avec le SHA-1 du certificat **release** (ou celui
   de la signature d'application Google Play) avant de publier.
5. **Où mettre les valeurs** — la même valeur partout, l'ID client **Web** :
   - serveur : variable d'environnement `NDF_GOOGLE_CLIENT_ID=<ID client Web>` (lu par
     `app.google.client-id` dans `application.yml`) ;
   - app : `buildGoogleServerClientId` dans `app/lib/data/server_config.dart`, ou au lancement
     `flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<ID client Web>`.
6. **Vérifier** : relancer le serveur et l'app ; la page Compte affiche « Continuer avec Google ».
   Erreurs fréquentes : 503 → `NDF_GOOGLE_CLIENT_ID` absent ; « Connexion Google impossible sur
   cet appareil » → SHA-1 ou nom de paquet de l'identifiant Android incorrects, ou compte absent
   des utilisateurs test ; 401 → l'app et le serveur n'utilisent pas le même ID client Web.

## Phase 4 : documents synchronisés sur le serveur

Même principe que les dépenses : l'appareil fait foi tant que ses changements ne sont pas envoyés,
identifiants UUID générés par le client, envois idempotents, suppressions logiques, isolation par
compte (identifiant étranger → 404). **Pas d'analyse IA** : le rendu recadré/filtré est calculé sur
l'appareil et envoyé tel quel avec l'original.

**Modèle serveur (paquet `document`).** `Document` : id, `ownerId`, titre (1 à 200 caractères),
`pageOrder` (liste ordonnée des identifiants de pages voulus par l'appareil), dates, `deleted`.
`DocumentPage` : id, `documentId`, original (écriture unique) et son type, rendu (remplaçable),
filtre, contour, `sizeBytes` (original + rendu), `renderVersion` (1, puis +1 à chaque nouveau
rendu), `removed` (retrait logique : page absente de `pageOrder`). Fichiers dans
`<storage-dir>/documents/<pageId>/` (racine distincte de celle des dépenses : un identifiant de page
ne peut pas viser le dossier d'une dépense). **Quota** : un service `Quota` (paquet `account`) somme
l'usage des dépenses non supprimées et des pages non retirées de documents non supprimés ;
`QuotaExceededException` y déménage (elle concerne l'offre, pas la dépense).

**API** (Bearer, comme `/api/expenses`) :

| Endpoint | Résultat |
|---|---|
| `PUT /api/documents/{id}` `{title, pageIds}` | 200 `DocumentDto` ; crée le document s'il n'existe pas, sinon renomme et réordonne ; les pages déjà reçues absentes de `pageIds` sont retirées (logiquement), un identifiant pas encore reçu garde sa place pour la page envoyée ensuite ; 400 titre vide ou trop long |
| `POST /api/documents/{id}/pages` multipart `pageId, original, processed, filter, corners` | 200 `PageDto` ; idempotent par `pageId` (renvoi = page existante, original intact) ; 403 `QUOTA_EXCEEDED` si `usage + original + rendu > quota` ; 415 type non image (rendu : JPEG) |
| `POST /api/documents/{id}/pages/{pageId}/processed` multipart `processed, filter, corners` | 200 `PageDto` ; remplace le rendu, `renderVersion` +1, taille mise à jour ; l'original ne change pas ; pas de refus pour quota (comme le re-traitement d'une dépense) |
| `DELETE /api/documents/{id}` | 204 ; suppression logique (libère le quota, fichiers conservés) |
| `GET /api/documents/changes?since=` | documents du compte modifiés depuis (suppressions comprises) |
| `GET /api/documents/{id}` | `DocumentDto` |
| `GET /api/documents/{id}/pages/{pageId}/original` · `/processed` | octets |

`DocumentDto` = `{id, title, pages: [{id, filter, corners, renderVersion}], deleted, createdAt,
updatedAt}` ; `pages` = pages reçues et non retirées, dans l'ordre de `pageOrder`. Tout changement de
page met à jour `updatedAt` du document (donc le fait remonter dans `changes`).

**Synchro (app).** Le document porte un `SyncState` (`pendingUpload` à la création, `pendingUpdate`
après un renommage / ajout / retrait / réajustement, `pendingDelete`) et chaque page le sien
(`pendingUpload`, `pendingReprocess` après réajustement, `synced`) + sa `renderVersion`. Envoi d'un
document en attente : `PUT` (titre + ordre complet des pages locales), puis chaque page non envoyée
(`POST pages`) ou réajustée (`POST …/processed`), puis le document est marqué envoyé — seulement s'il
n'a pas changé entre-temps (sinon il repart à la synchro suivante). Quota dépassé → le document
reste en attente, compté dans le rapport, retenté à la synchro suivante (comme les dépenses). Réception
(`changes` depuis une date propre aux documents) : un document en attente localement n'est pas
écrasé ; sinon titre, ordre et pages viennent du serveur. **Fichiers téléchargés à la synchro** (le
plus simple, comme les dépenses : un document reçu est consultable et exportable hors-ligne) :
original et rendu d'une page nouvelle, rendu seul quand `renderVersion` a changé. Sans compte,
rien ne change (documents locaux, en attente d'envoi) ; à la connexion ils partent vers le compte.
Le client HTTP commun (en-têtes, erreurs 401/403/hors-ligne) est extrait d'`ExpenseApi`.

**Plan de tests.** Serveur : création / renommage / ordre / retrait (service, `@DataJpaTest`) ; page
idempotente, original intact ; nouveau rendu (original intact, version +1, taille) ; quota (refus
403, usage = dépenses + documents, retrait et suppression libèrent) ; isolation 404 et 401 (flux
`@SpringBootTest`) ; `changes`. App : `DocumentApi` (faux HTTP) ; transitions de `SyncState` du
domaine ; migration SQLite ; `DocumentSyncService` (envoi, rejouable hors-ligne, quota, réception
avec téléchargement, document local en attente non écrasé, suppression propagée) ;
`DocumentRepository` (synchro seulement connecté) ; page Compte (message de quota avec documents).

## Plan de tests (ordre)

Serveur : hash et vérification du mot de passe ; inscription (201, 409, 400) ; connexion (200, 401) ;
jeton haché en base, expiré refusé, révoqué après déconnexion ; `/api/expenses` sans jeton → 401 ;
un compte ne voit pas / ne modifie pas / ne supprime pas la dépense d'un autre (404) ;
`GET /api/account`. Phase 2 : taille comptée à l'envoi ; refus au-delà du quota ; suppression
logique libère le quota (tranché : oui, fichiers conservés mais non comptés) ;
pas d'appel à `ReceiptExtractor` en Gratuit (double de test) ; changement de plan par l'admin.
App : client d'authentification (faux HTTP) ; stockage du jeton (double) ; écran Compte (widget
tests : formulaire, erreurs, état connecté, déconnexion) ; synchro avec `Authorization`.

## Alternatives écartées

- JWT : non révocable à la déconnexion sans liste noire.
- Spring Security complet : trop lourd pour un en-tête de jeton et un hash de mot de passe.
- Compte obligatoire au démarrage : contraire au principe hors-ligne d'abord.
