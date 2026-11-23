package fr.notedefrais.account;

/** Jeton d'identité Google refusé : falsifié, expiré, mal formé ou destiné à une autre application. */
public class InvalidGoogleTokenException extends RuntimeException {
    public InvalidGoogleTokenException() {
        super("Connexion Google refusée : jeton invalide ou expiré");
    }
}
