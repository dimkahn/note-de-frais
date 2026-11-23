package fr.notedefrais.account;

/** Résultat d'une inscription ou d'une connexion : le jeton (à remettre au client, jamais stocké) et le compte. */
public record Authentication(String token, Account account) {}
