---
paths:
  - "app/**"
---
# Flutter / Dart

- Respecter `flutter analyze` (zéro avertissement) et `dart format`.
- `lib/<domaine>/` puis couches : `data/` (SQLite, HTTP, fichiers, plugins natifs), `domain/` (modèles
  immuables, règles, pur Dart), `ui/` (écrans et widgets). Les widgets n'appellent jamais HTTP ou SQLite
  directement. Transverse dans `lib/shared/`, navigation dans `lib/shell/`. Tests en miroir dans `test/`.
- Hors-ligne d'abord : toute action écrit d'abord en local, la synchro serveur est asynchrone et rejouable.
- L'original photographié est copié dans le stockage de l'app avant tout traitement et n'est jamais modifié.
- Widgets petits et `const` quand possible ; extraire un widget plutôt qu'une méthode `_buildX` longue.
- Tests : `flutter_test` ; unitaires pour `*/domain/` et `*/data/` (avec faux HTTP / base en mémoire),
  widget tests pour les écrans principaux.
- UI : Material 3, libellés en français, cibles tactiles ≥ 48 px, contrastes suffisants,
  `Semantics` sur les images de justificatifs. Pour une revue UI, utiliser le skill `apple-design`.
