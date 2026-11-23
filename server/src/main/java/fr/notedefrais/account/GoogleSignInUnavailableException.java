package fr.notedefrais.account;

/** La connexion Google ne peut pas être vérifiée : non configurée sur ce serveur, ou Google injoignable. */
public class GoogleSignInUnavailableException extends RuntimeException {
    public GoogleSignInUnavailableException(String message) {
        super(message);
    }

    public GoogleSignInUnavailableException(String message, Throwable cause) {
        super(message, cause);
    }
}
