package fr.notedefrais.account;

public class AccountNotFoundException extends RuntimeException {
    public AccountNotFoundException(String email) {
        super("Compte introuvable : " + email);
    }
}
