---
name: refactor
description: Refactoring sûr du code de note-de-frais sans changer le comportement — identifier les code smells, appliquer des transformations nommées par petites étapes sous tests verts. À utiliser quand on demande de nettoyer, simplifier, restructurer ou découper du code.
---

# Refactoring sûr

Cible : `$ARGUMENTS` (fichier, classe ou paquet ; à défaut, les fichiers modifiés récemment).

1. **Filet de sécurité** : lancer la suite du module. Si elle est rouge, s'arrêter et le signaler.
   Si la zone n'est pas couverte, écrire d'abord des tests de caractérisation (comportement actuel, même étrange).
2. **Diagnostic** : lister les smells trouvés avec `fichier:ligne`, la transformation proposée
   (Extract Method, Move Function, Replace Conditional with Polymorphism, Introduce Parameter Object…)
   et le bénéfice attendu. Prioriser par valeur / risque.
3. **Exécution** : une transformation à la fois ; tests après chacune ; préférer les outils de
   refactoring de l'IDE (renommage, déplacement) aux remplacements texte.
4. **Interdits** : modifier le comportement, modifier des assertions de test pour « faire passer »,
   ajouter des fonctionnalités au passage. Une anomalie découverte → la noter, ne pas la corriger ici.
5. **Bilan** : liste des transformations appliquées, suite verte (résultat réel), smells restants volontairement laissés.
