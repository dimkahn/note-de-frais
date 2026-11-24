# `shell` (app) — coquille et navigation

- `MainShell` : onglets Dépenses / Documents / Compte (état conservé) et bouton rond central
  **Scanner** (seul point d'entrée du scan). Mode de départ : Document depuis l'onglet Documents,
  Ticket sinon. Après un ticket → onglet Dépenses ; après un document → sa fiche.
  Le scan est injectable (`ShellScanner`, défaut `scanAndSave`) pour les tests.
- `LaunchScreen` : page de chargement au démarrage.

Tests : `test/shell/**`.
