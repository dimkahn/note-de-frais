package fr.notedefrais.account;

import java.util.UUID;

/** Limites de l'offre d'un compte (quota, analyse IA). */
@FunctionalInterface
public interface AccountLimits {
    PlanLimits limitsOf(UUID accountId);
}
