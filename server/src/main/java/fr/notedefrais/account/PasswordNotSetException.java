package fr.notedefrais.account;

/** Connexion par mot de passe à un compte qui n'en a pas (créé par la connexion Google). */
public class PasswordNotSetException extends RuntimeException {
    public PasswordNotSetException() {
        super("Ce compte n'a pas de mot de passe : connectez-vous avec Google");
    }
}
