package fr.notedefrais.config;

import fr.notedefrais.account.Plan;
import fr.notedefrais.account.PlanLimits;
import java.time.Duration;
import java.util.Map;
import java.util.stream.Collectors;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.util.unit.DataSize;

/**
 * @param storageDir dossier racine des justificatifs (originaux + versions traitées)
 * @param apiToken   jeton d'administration exigé dans l'en-tête {@code X-Api-Token} sur {@code /api/admin/**}
 * @param sessionTtl durée de validité d'une session ouverte par une connexion
 * @param claude     configuration de l'extraction
 * @param plans      ce que permet chaque offre
 * @param google     connexion Google
 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(String storageDir, String apiToken, Duration sessionTtl, Claude claude,
                            Map<Plan, Offer> plans, Google google) {

    /**
     * @param quota      espace de stockage en ligne (ex. {@code 100MB})
     * @param aiAnalysis analyse des justificatifs par Claude incluse
     */
    public record Offer(DataSize quota, boolean aiAnalysis) {}

    public Map<Plan, PlanLimits> planLimits() {
        if (plans == null) throw new IllegalStateException("Offres non configurées (app.plans)");
        return plans.entrySet().stream().collect(Collectors.toMap(Map.Entry::getKey,
                e -> new PlanLimits(e.getValue().quota().toBytes(), e.getValue().aiAnalysis())));
    }

    /**
     * @param clientId identifiant client OAuth « web » attendu dans les jetons Google ; vide = connexion Google fermée
     */
    public record Google(String clientId) {

        public boolean enabled() {
            return clientId != null && !clientId.isBlank();
        }
    }

    /**
     * @param enabled   active l'extraction automatique
     * @param model     modèle Claude utilisé
     * @param maxTokens limite de sortie
     */
    public record Claude(boolean enabled, String model, long maxTokens) {}
}
