package fr.notedefrais.document;

import fr.notedefrais.receipt.imaging.ImageFilter;
import fr.notedefrais.receipt.imaging.Rotation;
import org.hibernate.annotations.ColumnDefault;
import jakarta.persistence.*;
import java.util.UUID;

/** Page d'un document : original photographié (jamais modifié) et rendu calculé sur l'appareil. */
@Entity
@Table(name = "document_page", indexes = {
        @Index(name = "idx_document_page_document", columnList = "documentId"),
        @Index(name = "idx_document_page_owner", columnList = "ownerId")
})
public class DocumentPage {

    @Id
    private UUID id;
    private UUID documentId;
    private UUID ownerId;
    private String originalFile;
    private String originalContentType;
    private long originalSizeBytes;
    private String processedFile;
    @Enumerated(EnumType.STRING)
    private ImageFilter filter;
    /** Contour choisi sur l'appareil ({@link fr.notedefrais.receipt.imaging.Quad#format()}). */
    private String corners;
    /** Quart de tour horaire du rendu calculé sur l'appareil, en degrés (pour le réajuster ailleurs). */
    @ColumnDefault("0")
    @Column(nullable = false)
    private int rotation;
    /** Place occupée en ligne (original + rendu courant). */
    private long sizeBytes;
    /** 1 au premier envoi, +1 à chaque nouveau rendu : l'appareil sait quand le retélécharger. */
    private int renderVersion;
    /** Retirée du document (absente de son ordre) : ne compte plus, l'original reste stocké. */
    private boolean removed;

    protected DocumentPage() {}

    public DocumentPage(UUID id, UUID documentId, UUID ownerId, String originalFile, String originalContentType,
                        long originalSizeBytes) {
        this.id = id;
        this.documentId = documentId;
        this.ownerId = ownerId;
        this.originalFile = originalFile;
        this.originalContentType = originalContentType;
        this.originalSizeBytes = originalSizeBytes;
        this.sizeBytes = originalSizeBytes;
    }

    /** Nouveau rendu (premier ou suivant) ; l'original ne change pas. */
    public void render(String fileName, long processedSizeBytes, ImageFilter newFilter, String newCorners,
                       Rotation newRotation) {
        processedFile = fileName;
        sizeBytes = originalSizeBytes + processedSizeBytes;
        filter = newFilter;
        corners = newCorners;
        rotation = (newRotation == null ? Rotation.NONE : newRotation).degrees();
        renderVersion++;
    }

    public void setRemoved(boolean removed) { this.removed = removed; }

    public boolean belongsTo(UUID owner, UUID document) {
        return ownerId.equals(owner) && documentId.equals(document);
    }

    public UUID getId() { return id; }
    public UUID getDocumentId() { return documentId; }
    public String getOriginalFile() { return originalFile; }
    public String getOriginalContentType() { return originalContentType; }
    public String getProcessedFile() { return processedFile; }
    public ImageFilter getFilter() { return filter; }
    public String getCorners() { return corners; }
    public Rotation getRotation() { return Rotation.ofDegrees(rotation); }
    public long getSizeBytes() { return sizeBytes; }
    public int getRenderVersion() { return renderVersion; }
    public boolean isRemoved() { return removed; }
}
