package fr.notedefrais.account;

/**
 * Ce qu'une offre permet.
 *
 * @param quotaBytes espace de stockage en ligne (originaux + rendus)
 * @param aiAnalysis analyse des justificatifs par Claude incluse
 */
public record PlanLimits(long quotaBytes, boolean aiAnalysis) {}
