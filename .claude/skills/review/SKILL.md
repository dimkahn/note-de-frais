---
name: review
description: Relire les changements en cours de note-de-frais selon les règles du projet (TDD, conception, refactoring, sécurité, invariants métier) avant de déclarer une tâche terminée.
---

# Relecture

1. Lister les fichiers modifiés (`git status --short`, `git diff`).
2. Lancer l'agent `code-reviewer` avec cette liste et le contexte de la tâche.
3. Lancer les suites concernées (`mvn -q test`, `flutter test`, `flutter analyze`) et rapporter le résultat réel.
4. Présenter les constats classés : bloquant / à corriger / suggestion, chacun avec `fichier:ligne`.
5. Proposer les corrections ; ne les appliquer que si l'utilisateur le demande ou si elles sont triviales et sûres.
