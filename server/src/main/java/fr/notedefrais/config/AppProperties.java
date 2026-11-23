package fr.notedefrais.config;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * @param storageDir dossier racine des justificatifs (originaux + versions traitées)
 * @param apiToken   jeton d'administration exigé dans l'en-tête {@code X-Api-Token} sur {@code /api/admin/**}
 * @param sessionTtl durée de validité d'une session ouverte par une connexion
 * @param claude     configuration de l'extraction
 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(String storageDir, String apiToken, Duration sessionTtl, Claude claude) {

    /**
     * @param enabled   active l'extraction automatique
     * @param model     modèle Claude utilisé
     * @param maxTokens limite de sortie
     */
    public record Claude(boolean enabled, String model, long maxTokens) {}
}
