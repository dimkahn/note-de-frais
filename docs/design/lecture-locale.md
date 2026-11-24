# Lecture du justificatif sur l'appareil (pré-remplissage hors-ligne)

## Besoin
Sans serveur (ou en attendant son analyse), l'utilisateur doit tout saisir à la main. On lit le texte du
justificatif sur le téléphone (OCR Google ML Kit, hors-ligne, gratuit) et on en déduit par des règles
le **montant TTC**, la **TVA**, la **date**, la **devise** et le **commerçant**, pour pré-remplir la fiche.
L'analyse Claude du serveur reste la référence quand elle est disponible.

Critères d'acceptation
- Étant donné un ticket scanné sans serveur, quand la lecture locale aboutit, alors la fiche affiche
  montant, TVA, date, devise et commerçant trouvés, signalés « À vérifier ».
- Étant donné une fiche pré-remplie, quand je corrige et enregistre, alors c'est une correction manuelle
  (`userEdited`) et plus rien ne l'écrase.
- Étant donné un serveur configuré, tant que son analyse n'est pas terminée, le pré-remplissage reste
  affiché ; quand elle est terminée (`DONE`), les valeurs du serveur remplacent le pré-remplissage.
- Si l'analyse serveur échoue, le pré-remplissage reste affiché.
- La lecture ne bloque jamais l'enregistrement : la dépense est créée d'abord, pré-remplie ensuite.
- Une lecture qui échoue (desktop, erreur ML Kit, texte illisible) laisse la fiche vide, sans erreur bloquante.

## Invariants touchés
- Original intact : l'OCR lit l'image recadrée (copie), n'écrit rien.
- `userEdited` : le pré-remplissage ne s'applique jamais à une dépense corrigée à la main, ni ne pose
  `userEdited`. Il ne déclenche **aucun** envoi `PUT` (qui vaudrait correction manuelle côté serveur).
- UUID client, suppression logique : inchangés.

## Modèle
- `Expense.prefilled` (bool) : champs issus de la lecture locale, non confirmés.
- `ReceiptGuess` (domaine) : `merchant`, `expenseDate`, `amountTotal`, `amountVat`, `currency`, tous optionnels.
- SQLite : colonne `prefilled INTEGER NOT NULL DEFAULT 0`, migration v2 → v3.
- Serveur : **aucun changement** (le pré-remplissage reste local à l'appareil).

## API
Aucune modification.

## Hors-ligne / synchro
- Lecture 100 % sur l'appareil, aucun réseau.
- `Expense.withDeviceGuess(guess)` : sans effet si `userEdited`, si l'analyse serveur est `DONE`, ou si un
  champ est déjà rempli (on ne complète que les champs vides). Ne change pas `syncState`.
- Fusion synchro (`SyncService._merge`) : si la copie locale est `prefilled` et que le serveur n'a pas fini
  (`status != DONE`), on garde les champs pré-remplis ; dès `DONE`, le serveur l'emporte et `prefilled` repasse à faux.
- La lecture est relue depuis la base juste avant d'appliquer le résultat (une synchro a pu passer entre-temps).

## Couches
- `app/lib/scan/domain/receipt_parser.dart` : `ReceiptParser.parse(String texte) → ReceiptGuess`, pur Dart, règles
  pour tickets/factures français (montants `12,50` / `1 234,56`, mots-clés TOTAL/TTC/NET À PAYER, TVA,
  dates `jj/mm/aaaa`, `jj.mm.aa`, `12 mars 2026`, devise €/EUR/CHF/$/£, commerçant = première ligne significative).
- `app/lib/expense/domain/expense.dart` : `prefilled`, `withDeviceGuess`.
- `app/lib/scan/domain/receipt_text_reader.dart` : interface `ReceiptTextReader { Future<String?> read(String imagePath) }`
  (frontière), implémentation `MlKitReceiptTextReader` (`google_mlkit_text_recognition`, script latin).
- `app/lib/expense/data/expense_repository.dart` : après `captureScan`, lecture en arrière-plan → `withDeviceGuess` → enregistrement local.
- `app/lib/expense/data/sync_service.dart` : règle de fusion ci-dessus.
- `app/lib/expense/ui` : badge « À vérifier » et carte d'explication sur la fiche.
- `main.dart` : lecteur ML Kit sur Android/iOS, aucun lecteur sur desktop.

## Plan de tests (ordre TDD)
1. `ReceiptParser` : total TTC, priorité « TOTAL TTC » sur sous-totaux, TVA, date numérique, date en lettres,
   devise, commerçant, texte vide → rien.
2. `Expense.withDeviceGuess` : complète les vides et marque `prefilled` ; ignoré si `userEdited` ; ignoré si `DONE` ;
   ne touche pas `syncState`. `withEditedFields` remet `prefilled` à faux.
3. `LocalStore` : `prefilled` persisté ; migration v2 → v3.
4. `SyncService` : pré-remplissage conservé tant que le serveur traite ; remplacé à `DONE`.
5. `ExpenseRepository.captureScan` avec un faux lecteur : la dépense est pré-remplie ; un lecteur en erreur n'empêche rien.
6. `statusBadge` : « À vérifier » ; widget : carte sur la fiche.

## Alternatives écartées
- ML Kit Entity Extraction : télécharge un modèle par langue au premier usage (pas hors-ligne d'emblée),
  et des règles suffisent pour dates et montants.
- Petits modèles vision-langage sur l'appareil (Gemma 3n, Gemini Nano…) : 1–3 Go ou téléphones compatibles
  seulement ; plusieurs secondes par ticket.
- Envoyer le pré-remplissage au serveur : changerait l'API et risquerait de passer pour une correction manuelle.
