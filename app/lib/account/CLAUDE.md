# Domaine `account` (app) — connexion au compte

Contrepartie serveur : `server/…/account/`. Conception : `docs/design/comptes-et-offres.md`.

- `domain/account.dart` : `Plan` (aligné sur l'énumération serveur), compte et usage.
- `data/` : `AccountRepository` (session, adresse du serveur, envoi des données locales à la connexion),
  `AuthApi`, `GoogleAuth`, `BiometricAuth` + `DeviceKeyStore` (connexion par empreinte), `SessionStore`.
- `ui/account_screen.dart` : onglet Compte (connexion, inscription, offre, Avancé › adresse du serveur).

Invariants propres
- Sans session, l'app reste pleinement utilisable hors-ligne : la connexion n'est jamais un prérequis.
- Jeton de session et clé d'appareil en stockage sécurisé, jamais journalisés.
- Messages de refus du serveur affichés tels quels (`AuthException`).

Tests : `test/account/**` ; doubles dans `test/support/` (`fake_server`, `fake_google_auth`,
`fake_biometric_auth`, `memory_*_store`, `signed_out_account`).
