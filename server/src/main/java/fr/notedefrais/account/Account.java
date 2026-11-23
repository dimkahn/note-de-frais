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
    /** Hash BCrypt ; jamais le mot de passe en clair. Absent pour un compte créé par Google. */
    private String passwordHash;
    /** Identifiant Google ({@code sub}) du compte lié, s'il y en a un. */
    @Column(unique = true)
    private String googleSubject;
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

    static Account fromGoogle(String email, String googleSubject) {
        Account account = new Account(email, null);
        account.googleSubject = googleSubject;
        return account;
    }

    @PrePersist
    void onCreate() {
        createdAt = Instant.now();
    }

    /** Le mot de passe éventuel est retiré : désormais, seul Google ouvre ce compte. */
    void linkGoogle(String subject) {
        googleSubject = subject;
        passwordHash = null;
    }

    void changePlan(Plan newPlan) {
        plan = newPlan;
    }

    public UUID getId() { return id; }
    public String getEmail() { return email; }
    String getPasswordHash() { return passwordHash; }
    public Plan getPlan() { return plan; }
    public Instant getCreatedAt() { return createdAt; }
    String getGoogleSubject() { return googleSubject; }
}
