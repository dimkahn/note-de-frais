package fr.notedefrais.account;

/**
 * Identité attestée par un jeton Google vérifié.
 *
 * @param subject       identifiant Google stable du compte ({@code sub})
 * @param email         adresse e-mail du compte Google
 * @param emailVerified Google certifie que l'adresse appartient au titulaire du compte
 */
public record GoogleIdentity(String subject, String email, boolean emailVerified) {}
