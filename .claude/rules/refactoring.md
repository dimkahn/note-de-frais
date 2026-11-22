# Refactoring

- Uniquement quand les tests sont verts ; relancer après chaque petite étape.
- Ne jamais mélanger refactoring et changement de comportement dans la même étape (ni le même commit).
- Petites transformations nommées (Fowler) : Extract Method/Class, Rename, Inline, Move,
  Replace Conditional with Polymorphism, Introduce Parameter Object, Replace Magic Number…
- Signaux à traiter : méthode > ~25 lignes, classe > ~250 lignes ou à plusieurs responsabilités,
  duplication (règle de trois), paramètres booléens, longues listes de paramètres,
  envie de fonctionnalité (feature envy), obsession des primitives (montant → `BigDecimal` + devise).
- Utiliser les outils de l'IDE (rename_refactoring) quand disponibles plutôt que des remplacements texte.
- Supprimer le code mort plutôt que le commenter.
