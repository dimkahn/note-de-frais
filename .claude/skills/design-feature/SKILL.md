---
name: design-feature
description: Concevoir une fonctionnalité de note-de-frais avant de coder — modèle de données, API REST, flux hors-ligne/synchro, découpage en couches et plan de tests. À utiliser pour toute fonctionnalité qui touche plus d'une classe ou à la fois serveur et app.
---

# Conception d'une fonctionnalité

Fonctionnalité : `$ARGUMENTS`

Produire, dans cet ordre, un document court (dans la conversation, ou `docs/design/<slug>.md` si demandé) :

1. **Besoin** : qui, quoi, pourquoi ; critères d'acceptation vérifiables (Given/When/Then).
2. **Invariants touchés** (voir CLAUDE.md : original intact, UUID client, `userEdited`, suppression logique).
3. **Modèle** : entités/records modifiés, migrations de schéma (serveur et SQLite app), compatibilité des données existantes.
4. **API** : endpoints, verbes, codes HTTP, DTO JSON d'exemple ; rétrocompatibilité avec l'app déjà installée.
5. **Hors-ligne / synchro** : que se passe-t-il sans réseau, conflits, rejouabilité (idempotence).
6. **Couches** : quelles classes dans `expense` / `imaging` / `extraction` / `storage` / `web` et
   `app/lib/{domain,data,ui}` ; nouvelles interfaces de frontière éventuelles.
7. **Plan de tests** : liste d'exemples ordonnés pour le skill `/tdd` (unitaires d'abord).
8. **Alternatives écartées** : 1 à 2 lignes chacune, avec la raison.

Faire valider ce plan par l'utilisateur si un choix structurant est ambigu, puis enchaîner avec `/tdd`.
Pour l'aspect visuel d'un écran, s'appuyer sur le skill `apple-design` (fonctionne pour Flutter).
