package fr.notedefrais.account;

/** Message volontairement identique pour un e-mail inconnu et un mauvais mot de passe. */
public class InvalidCredentialsException extends RuntimeException {
    public InvalidCredentialsException() {
        super("E-mail ou mot de passe incorrect");
    }
}
