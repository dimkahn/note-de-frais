package fr.notedefrais.account.web;

import fr.notedefrais.account.Authentication;

/** Réponse à une inscription ou une connexion : jeton de session à présenter en {@code Authorization: Bearer}. */
public record AuthResponse(String token, AccountDto account) {

    static AuthResponse of(Authentication auth) {
        return new AuthResponse(auth.token(), AccountDto.of(auth.account()));
    }
}
