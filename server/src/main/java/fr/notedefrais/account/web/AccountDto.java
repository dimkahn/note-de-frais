package fr.notedefrais.account.web;

import fr.notedefrais.account.Account;
import fr.notedefrais.account.Plan;

/** Représentation JSON du compte connecté. */
public record AccountDto(String email, Plan plan) {

    static AccountDto of(Account account) {
        return new AccountDto(account.getEmail(), account.getPlan());
    }
}
