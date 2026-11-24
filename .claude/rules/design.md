# Conception

- **Découpage par domaine fonctionnel** (carte dans `CLAUDE.md`) : `account`, `expense`, `document`,
  `receipt` (serveur) / `scan` (app), `export` (app) ; le transverse va dans `storage`, `web`, `config`
  (serveur) ou `shared`, `shell` (app). Pas de paquets « utils » fourre-tout. Chaque domaine a son
  `CLAUDE.md` (responsabilité, invariants, frontières, tests) : le tenir à jour quand le domaine change.
- Dépendances entre domaines à sens unique quand c'est possible ; un nouveau domaine = un dossier côté
  serveur et/ou app + son `CLAUDE.md`.
- **Dépendances vers le métier** : le domaine ne connaît ni HTTP, ni OpenCV, ni le SDK Anthropic.
  Les intégrations externes sont derrière une interface définie côté métier
  (`ReceiptExtractor`, `ImageProcessor`, `FileStorage`).
- **Immuabilité par défaut** : `record` Java, classes Dart `final` avec `copyWith`.
- Valider aux frontières (DTO + Bean Validation, parsing JSON côté Flutter) ; le cœur suppose des données valides.
- Erreurs : exceptions métier explicites, traduites en réponses HTTP en un seul endroit
  (`@RestControllerAdvice`). Ne jamais avaler une exception silencieusement.
- Nommage métier en français cohérent avec l'existant (Category, Expense… pour le code, libellés UI en français).
- Pas de configuration en dur : `application.yml` / réglages de l'app.
- YAGNI : ne pas ajouter d'option, de couche ou d'abstraction sans besoin présent.
- Sécurité : jamais de secret dans le code ou les logs ; la clé Anthropic vient de l'environnement.
