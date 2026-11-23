package fr.notedefrais.account;

/** Identité Google valide, mais qui ne peut ni ouvrir ni être liée à un compte (prise de contrôle évitée). */
public class GoogleAccountRefusedException extends RuntimeException {
    public GoogleAccountRefusedException(String message) {
        super(message);
    }
}
