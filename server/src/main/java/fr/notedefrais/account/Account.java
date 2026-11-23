package fr.notedefrais.account;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

@Entity
@Table(name = "account")
public class Account {

    @Id
    private UUID id;
    /** Toujours en minuscules (normalisé par {@link AccountService}). */
    @Column(nullable = false, unique = true)
    private String email;
    /** Hash BCrypt ; jamais le mot de passe en clair. */
    private String passwordHash;
    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private Plan plan = Plan.FREE;
    private Instant createdAt;

    protected Account() {}

    Account(String email, String passwordHash) {
        this.id = UUID.randomUUID();
        this.email = email;
        this.passwordHash = passwordHash;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    public UUID getId() { return id; }
    public String getEmail() { return email; }
    String getPasswordHash() { return passwordHash; }
    public Plan getPlan() { return plan; }
    public Instant getCreatedAt() { return createdAt; }
}
