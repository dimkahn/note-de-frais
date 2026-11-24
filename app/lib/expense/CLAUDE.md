# Domaine `expense` (app) — dépenses

Contrepartie serveur : `server/…/expense/`. Conception : `docs/design/lecture-locale.md`.

- `domain/` : `Expense` (+ `Category` aligné serveur), `ExpenseQuery` (filtres locaux), `Money`
  (montants en texte décimal, additionnés en centimes, jamais en `double`).
  `categoryBreakdown` : part de chaque type dans le total (une seule devise, sinon rien).
- `data/` : `ExpenseRepository` (point d'entrée de l'UI, écrit d'abord en local), `ExpenseApi`
  (`/api/expenses`), `SyncService` (pousse les changements locaux puis récupère `/changes`).
- `ui/` : onglet Dépenses (`home_screen`), fiche (`expense_detail_screen`), tuile,
  `status_badge.dart` (statut affiché : envoi, analyse, à vérifier / compléter), `ReceiptImage`, `TicketCard`.
  `category_style.dart` : couleur + icône par type (`CategoryBadge`), utilisées partout où un type s'affiche ;
  teintes foncées pour un pictogramme blanc ≥ 3:1.

Invariants propres
- Hors-ligne d'abord : toute action passe par `LocalStore` ; la synchro est rejouable et idempotente (UUID client).
- Fusion synchro : copie locale `prefilled` gardée tant que le serveur n'est pas `DONE` ; `userEdited` jamais écrasé.
- Original copié dans le stockage de l'app avant tout traitement, jamais modifié.
- Envoi refusé pour quota : la dépense reste en attente et sera retentée.

Tests : `test/expense/**` (données en SQLite mémoire, faux serveur HTTP).
