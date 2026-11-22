---
name: tdd
description: Implémenter un comportement en TDD strict (red / green / refactor) sur le serveur Spring ou l'app Flutter. À utiliser pour toute nouvelle fonctionnalité, correction de bug ou changement de règle métier dans note-de-frais.
---

# Cycle TDD

Argument : description du comportement à implémenter (`$ARGUMENTS`).

## 0. Cadrer
- Reformuler le comportement en une liste d'exemples concrets (entrée → sortie attendue),
  du cas nominal aux cas limites et d'erreur. Écrire cette liste (todo) avant tout code.
- Identifier la couche : domaine, service, contrôleur, data Flutter, widget.

## 1. Red (un exemple à la fois)
- Écrire **un seul** test pour le prochain exemple de la liste.
- Lancer uniquement ce test :
  - serveur : `cd server && mvn -q test -Dtest=NomDuTest`
  - app : `cd app && flutter test test/chemin_test.dart`
- Vérifier que l'échec est le bon (message d'assertion attendu). Sinon, corriger le test.

## 2. Green
- Code minimal pour passer. Les constantes en dur sont acceptables à ce stade si l'exemple suivant les forcera à généraliser (triangulation).
- Relancer le test, puis la suite du module.

## 3. Refactor
- Supprimer duplication et mauvais noms dans le code **et** les tests (voir `.claude/rules/refactoring.md`).
- Suite verte après chaque étape.

## 4. Boucler
- Cocher l'exemple, passer au suivant. Ajouter à la liste tout cas découvert en route.

## 5. Clôturer
- Suite complète du module verte : copier le résumé réel (nombre de tests, échecs).
- Lancer l'agent `code-reviewer` sur les fichiers modifiés si le changement dépasse une classe.
