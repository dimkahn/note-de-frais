package fr.notedefrais.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * @param storageDir dossier racine des justificatifs (originaux + versions traitées)
 * @param apiToken   jeton partagé exigé dans l'en-tête {@code X-Api-Token} (vide = désactivé)
 * @param claude     configuration de l'extraction
 */
@ConfigurationProperties(prefix = "app")
public record AppProperties(String storageDir, String apiToken, Claude claude) {

    /**
     * @param enabled   active l'extraction automatique
     * @param model     modèle Claude utilisé
     * @param maxTokens limite de sortie
     */
    public record Claude(boolean enabled, String model, long maxTokens) {}
}
