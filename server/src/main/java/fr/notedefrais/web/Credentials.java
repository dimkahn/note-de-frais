package fr.notedefrais.web;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

/** Corps des requêtes d'authentification par e-mail et mot de passe, ou par Google. */
public final class Credentials {

    private Credentials() {}

    /** Inscription : e-mail valide, mot de passe de 10 caractères au moins. */
    public record Registration(
            @NotBlank @Email(regexp = ".+@.+\\..+") @Size(max = 254) String email,
            @NotNull @Size(min = 10, max = 72) String password) {}

    /** Connexion : pas de règle de forme, pour ne rien révéler au-delà d'un refus uniforme. */
    public record Login(@NotBlank String email, @NotNull String password) {}

    /** Connexion Google : jeton d'identité obtenu par l'app auprès de Google (quelques Ko au plus). */
    public record Google(@NotBlank @Size(max = 4096) String idToken) {}
}
