package fr.notedefrais.account;

/** Comptes de test pour les couches qui ne passent pas par {@link AccountService}. */
public final class TestAccounts {

    private TestAccounts() {}

    public static Account free(String email) {
        return new Account(email, "hash");
    }
}
