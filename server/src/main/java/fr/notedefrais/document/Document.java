package fr.notedefrais.document;

import jakarta.persistence.*;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.UUID;

/** Document de plusieurs pages (contrat, attestation…), distinct d'une dépense. */
@Entity
@Table(name = "document", indexes = {
        @Index(name = "idx_document_owner_updated", columnList = "ownerId, updatedAt")
})
public class Document {

    /** Identifiant généré par le client : synchronisation hors-ligne sans doublon. */
    @Id
    private UUID id;
    private UUID ownerId;
    @Column(length = 200)
    private String title;
    /** Ordre voulu par l'appareil ; peut citer des pages pas encore reçues, qui y prendront leur place. */
    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "document_page_order", joinColumns = @JoinColumn(name = "document_id"))
    @OrderColumn(name = "position")
    @Column(name = "page_id")
    private List<UUID> pageOrder = new ArrayList<>();
    private Instant createdAt;
    private Instant updatedAt;
    /** Suppression logique pour que la suppression se propage aux autres appareils. */
    private boolean deleted;

    protected Document() {}

    public Document(UUID id, UUID ownerId, String title) {
        this.id = id;
        this.ownerId = ownerId;
        this.title = title;
    }

    @PrePersist
    void onCreate() {
        createdAt = updatedAt = Instant.now();
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    public boolean isOwnedBy(UUID accountId) {
        return ownerId.equals(accountId);
    }

    public void rename(String newTitle) {
        title = newTitle;
    }

    /** Un identifiant répété ne garde que sa première place. */
    public void reorder(List<UUID> pageIds) {
        pageOrder = new ArrayList<>(new LinkedHashSet<>(pageIds));
    }

    public boolean lists(UUID pageId) {
        return pageOrder.contains(pageId);
    }

    /** Une page a changé : le document remonte dans les changements à synchroniser. */
    public void touch() {
        updatedAt = Instant.now();
    }

    public void markDeleted() {
        deleted = true;
    }

    public UUID getId() { return id; }
    public UUID getOwnerId() { return ownerId; }
    public String getTitle() { return title; }
    public List<UUID> getPageOrder() { return List.copyOf(pageOrder); }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public boolean isDeleted() { return deleted; }
}
