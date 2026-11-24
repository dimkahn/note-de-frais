# Domaine `expense` (serveur) — dépenses et justificatifs

Contrepartie app : `app/lib/expense/`.

- `Expense` (entité, UUID fourni par le client), `ExpenseService` (création idempotente, mise à jour,
  suppression logique, `changesSince` pour la synchro), `ExpenseSpecs` (critères de recherche),
  `ExpenseSummary` (totaux par devise, sans conversion).
- `ExpenseProcessor` + `ProcessingQueue` (`AsyncProcessingQueue`, threads virtuels) : recadrage + filtre
  via `receipt/imaging`, puis extraction via `receipt/extraction` si l'offre inclut l'analyse IA
  (`AccountLimits`). L'upload répond avant le traitement.
- Rendu paramétré par filtre, coins et `Rotation` (stockée en degrés, défaut 0 en base) ; `null` au
  re-traitement = inchangé. API : `rotation` en degrés (0/90/180/270, sinon 400).
- `ProcessingStatus` : PENDING → DONE | EXTRACTION_FAILED | NOT_INCLUDED | FAILED.
- `expense/web/` : `/api/expenses/**` (multipart à la création, `/changes?since=`, `/reprocess`,
  `/original`, `/processed`).

Invariants propres
- `userEdited` : une saisie manuelle n'est jamais écrasée par une (ré)extraction (`Expense.applyExtraction`).
- Original en écriture unique (`FileStorage`) ; re-traitement = nouveau rendu, jamais l'original.
- `deleted` logique, visible dans `/changes` pour se propager.
- Pas d'appel Claude dans une transaction ouverte : le traitement se fait hors transaction.
- Montants `BigDecimal` + devise ; jamais de somme entre devises.

Tests : `ExpenseServiceTest`, `ExpenseSpecsTest`, `ExpenseSummaryTest`, `expense/web/ExpenseControllerTest`,
`ExpenseFlowTest` (bout en bout, `ReceiptExtractor` remplacé par un double).
