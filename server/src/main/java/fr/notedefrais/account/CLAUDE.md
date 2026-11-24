# Domaine `account` (serveur) — comptes, sessions, offres, quotas

Contrepartie app : `app/lib/account/`. Conception : `docs/design/comptes-et-offres.md`.

- `account/` : `Account`, `AccountService` (inscription, connexions mot de passe / Google / clé
  d'appareil, sessions), `Plan` + `PlanLimits` (lus dans `app.plans`), `Quota` = somme des `StorageUsage`
  fournis par les autres domaines (dépenses, documents).
- `account/web/` : `/api/auth/**`, `/api/account`, `/api/admin/**` (jeton `X-Api-Token`, voir
  `config/ApiTokenFilter`) ; `SessionAuthenticationFilter` exige `Authorization: Bearer` ailleurs.
- `account/google/` : implémentations de `GoogleIdentityVerifier` (seule dépendance à la bibliothèque Google).

Invariants propres
- Jetons de session et clés d'appareil : seul leur hash SHA-256 est stocké ; le jeton n'est jamais journalisé.
- Refus de connexion uniforme (`InvalidCredentialsException`) : ne rien révéler sur l'existence d'un e-mail.
- Une identité Google ne prend jamais le contrôle d'un compte existant non lié (`GoogleAccountRefusedException`).
- Quota : refus si `usage + taille de l'original > quota` ; le renvoi d'un UUID déjà connu n'est jamais
  refusé (idempotence) ; une suppression logique libère le quota.
- Ce domaine ne dépend pas de `expense` ni de `document` : ce sont eux qui exposent `StorageUsage`.

Tests : `AccountServiceTest` (unitaire, `TestAccounts`), `account/web/*Test` (`@WebMvcTest`),
`GoogleSignInFlowTest`, `PlanAndQuotaFlowTest`, `AccountIsolationFlowTest` (bout en bout).
