package fr.notedefrais.account;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/** Session ouverte par une connexion : seul le hash SHA-256 du jeton est conservé. */
@Entity
@Table(name = "account_session", indexes = @Index(name = "idx_session_account", columnList = "accountId"))
public class Session {

    @Id
    @Column(length = 64)
    private String tokenHash;
    @Column(nullable = false)
    private UUID accountId;
    @Column(nullable = false)
    private Instant expiresAt;

    protected Session() {}

    Session(String tokenHash, UUID accountId, Instant expiresAt) {
        this.tokenHash = tokenHash;
        this.accountId = accountId;
        this.expiresAt = expiresAt;
    }

    boolean isExpiredAt(Instant now) {
        return !now.isBefore(expiresAt);
    }

    public String getTokenHash() { return tokenHash; }
    public UUID getAccountId() { return accountId; }
    public Instant getExpiresAt() { return expiresAt; }
}
