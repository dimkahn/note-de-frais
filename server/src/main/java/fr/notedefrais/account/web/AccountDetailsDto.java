package fr.notedefrais.account.web;

import fr.notedefrais.account.Account;
import fr.notedefrais.account.Plan;
import fr.notedefrais.account.PlanLimits;

/** Compte connecté avec son offre, sa place utilisée en ligne et ce que l'offre permet. */
public record AccountDetailsDto(String email, Plan plan, long usedBytes, long quotaBytes, boolean aiAnalysis) {

    static AccountDetailsDto of(Account account, PlanLimits limits, long usedBytes) {
        return new AccountDetailsDto(account.getEmail(), account.getPlan(), usedBytes, limits.quotaBytes(),
                limits.aiAnalysis());
    }
}
