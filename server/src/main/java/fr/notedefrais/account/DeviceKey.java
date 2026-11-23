package fr.notedefrais.account;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.UUID;

/**
 * Clé d'appareil longue durée (connexion par empreinte) : seul le hash SHA-256 de la clé est
 * conservé. La révocation la supprime.
 */
@Entity
@Table(name = "device_key", indexes = @Index(name = "idx_device_key_account", columnList = "accountId"))
public class DeviceKey {

    @Id
    @Column(length = 64)
    private String keyHash;
    @Column(nullable = false)
    private UUID accountId;
    @Column(nullable = false, length = 100)
    private String label;
    @Column(nullable = false)
    private Instant createdAt;

    protected DeviceKey() {}

    DeviceKey(String keyHash, UUID accountId, String label, Instant createdAt) {
        this.keyHash = keyHash;
        this.accountId = accountId;
        this.label = label;
        this.createdAt = createdAt;
    }

    public String getKeyHash() { return keyHash; }
    public UUID getAccountId() { return accountId; }
    public String getLabel() { return label; }
    public Instant getCreatedAt() { return createdAt; }
}
