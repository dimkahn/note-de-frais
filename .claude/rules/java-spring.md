---
paths:
  - "server/**"
---
# Java 25 / Spring Boot 4

- Java moderne : `record`, `sealed`, pattern matching (`switch` sur types), `var` pour les locales évidentes, text blocks.
- Injection par constructeur uniquement (pas de `@Autowired` sur champ). Classes `final` quand possible.
- Contrôleurs minces : validation + délégation à un service. Pas de logique métier dans les
  sous-paquets `<domaine>/web` (contrôleurs + DTO du domaine) ; `web/` racine = transverse HTTP seulement.
- DTO `record` pour l'API ; ne jamais exposer l'entité JPA directement.
- Transactions au niveau service ; pas d'appel réseau (Claude) à l'intérieur d'une transaction ouverte.
- Montants en `BigDecimal`, dates en `LocalDate`/`Instant`, jamais `double` ni `Date`.
- Tests : JUnit 5 + AssertJ ; `@WebMvcTest` pour les contrôleurs, `@DataJpaTest` pour les requêtes,
  tests unitaires purs pour le traitement d'image (images synthétiques générées dans le test).
- Le SDK Anthropic n'est utilisé que dans `receipt/extraction/ClaudeReceiptExtractor` (voir skill `claude-api`).
