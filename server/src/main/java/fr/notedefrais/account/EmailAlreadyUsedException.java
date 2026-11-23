package fr.notedefrais.account;

public class EmailAlreadyUsedException extends RuntimeException {
    public EmailAlreadyUsedException() {
        super("Un compte existe déjà avec cette adresse e-mail");
    }
}
