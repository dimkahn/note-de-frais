package fr.notedefrais.account;

/** Vérifie un jeton d'identité émis par Google pour l'application (signature, émetteur, audience, validité). */
@FunctionalInterface
public interface GoogleIdentityVerifier {

    /**
     * @throws InvalidGoogleTokenException       jeton refusé (falsifié, expiré, destiné à une autre application…)
     * @throws GoogleSignInUnavailableException connexion Google non configurée ou Google injoignable
     */
    GoogleIdentity verify(String idToken);
}
