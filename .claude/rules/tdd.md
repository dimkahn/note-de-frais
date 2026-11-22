# TDD — Red / Green / Refactor

S'applique à tout code de production (`server/src/main/**`, `app/lib/**`).

1. **Red** : écrire d'abord un test qui exprime le comportement attendu, le lancer, constater
   qu'il échoue *pour la bonne raison* (assertion, pas erreur de compilation hors sujet).
2. **Green** : écrire le code minimal pour le faire passer. Pas d'anticipation.
3. **Refactor** : nettoyer code *et* tests, tests toujours verts. Voir `refactoring.md`.

Règles :
- Un test = un comportement. Nom en phrase : `rejette_un_montant_negatif`, `should crop the receipt when ...`.
- Structure Arrange / Act / Assert visible (lignes vides).
- Tester le comportement observable via l'API publique, pas les détails d'implémentation.
- Pas de mock sur ce qu'on possède quand un vrai objet léger suffit ; mocker les frontières
  (Claude API, système de fichiers distant, HTTP). Les appels Claude passent par une interface
  (`ReceiptExtractor`) remplacée par un double de test.
- Un bug corrigé commence par un test qui le reproduit.
- Ne jamais supprimer ou affaiblir un test pour le faire passer ; si le test est faux, l'expliquer.
- Pyramide : majorité de tests unitaires rapides ; tests d'intégration (`@SpringBootTest`,
  `@DataJpaTest`, widget tests) pour les coutures ; peu de tests de bout en bout.
- Lancer la suite concernée avant de déclarer une tâche terminée et rapporter le résultat réel.
