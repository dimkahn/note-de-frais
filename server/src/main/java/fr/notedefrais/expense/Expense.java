package fr.notedefrais.expense;

import fr.notedefrais.receipt.imaging.ImageFilter;
import fr.notedefrais.receipt.imaging.Rotation;
import jakarta.persistence.*;
import org.hibernate.annotations.ColumnDefault;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

@Entity
@Table(name = "expense", indexes = {
        @Index(name = "idx_expense_date", columnList = "expenseDate"),
        @Index(name = "idx_expense_category", columnList = "category"),
        @Index(name = "idx_expense_city", columnList = "city"),
        @Index(name = "idx_expense_updated", columnList = "updatedAt"),
        @Index(name = "idx_expense_owner", columnList = "ownerId")
})
public class Expense {

    /** Identifiant généré par le client : permet la synchronisation hors-ligne sans doublon. */
    @Id
    private UUID id;
    /** Compte propriétaire ; null pour les données de développement antérieures aux comptes. */
    private UUID ownerId;

    // --- Informations extraites (modifiables par l'utilisateur) ---
    private String merchant;
    @Enumerated(EnumType.STRING)
    private Category category;
    private LocalDate expenseDate;
    @Column(precision = 12, scale = 2)
    private BigDecimal amountTotal;
    @Column(precision = 12, scale = 2)
    private BigDecimal amountVat;
    @Column(length = 3)
    private String currency;
    private String city;
    private String country;
    private String address;
    private String paymentMethod;
    @Column(length = 2000)
    private String description;
    /** true si l'utilisateur a corrigé les champs : une ré-extraction ne les écrase pas. */
    private boolean userEdited;

    // --- Fichiers ---
    private String originalFile;
    private String originalContentType;
    private String processedFile;
    @Enumerated(EnumType.STRING)
    private ImageFilter filter = ImageFilter.ENHANCE;
    private boolean cropped;
    /** Contour choisi sur l'appareil ({@link fr.notedefrais.receipt.imaging.Quad#format()}) ; null = détection auto. */
    private String corners;
    /** Quart de tour horaire du rendu, en degrés. Défaut en base : les dépenses existantes ne sont pas pivotées. */
    @ColumnDefault("0")
    @Column(nullable = false)
    private int rotation;
    /** Place occupée en ligne (original + rendu) ; null pour les dépenses antérieures aux quotas. */
    private Long sizeBytes;

    // --- Traitement ---
    @Enumerated(EnumType.STRING)
    private ProcessingStatus status = ProcessingStatus.PENDING;
    @Column(length = 2000)
    private String processingError;
    @Lob
    private String extractionRaw;

    private Instant createdAt;
    private Instant updatedAt;
    /** Suppression logique pour que la suppression se propage aux autres appareils. */
    private boolean deleted;

    protected Expense() {}

    public Expense(UUID id) {
        this.id = id;
    }

    public Expense(UUID id, UUID ownerId) {
        this.id = id;
        this.ownerId = ownerId;
    }

    @PrePersist
    void onCreate() {
        createdAt = updatedAt = Instant.now();
    }

    @PreUpdate
    void onUpdate() {
        updatedAt = Instant.now();
    }

    // --- Comportement ---

    /** Correction par l'utilisateur : prioritaire sur toute extraction future. */
    public void applyManualEdit(ExpenseUpdate u) {
        applyFields(u);
        userEdited = true;
    }

    /** Résultat d'extraction : n'écrase jamais une correction manuelle. */
    public void applyExtraction(ExpenseUpdate u, String raw) {
        if (!userEdited) applyFields(u);
        extractionRaw = raw;
        status = ProcessingStatus.DONE;
        processingError = null;
    }

    /** @param totalSizeBytes place occupée par l'original et ce rendu */
    public void attachProcessedImage(String fileName, boolean wasCropped, long totalSizeBytes) {
        processedFile = fileName;
        cropped = wasCropped;
        sizeBytes = totalSizeBytes;
    }

    /** Rendu produit sans analyse IA : les champs (lus sur l'appareil ou corrigés) restent tels quels. */
    public void markAnalysisNotIncluded() {
        status = ProcessingStatus.NOT_INCLUDED;
        processingError = null;
    }

    public void markFailed(ProcessingStatus failure, String error) {
        status = failure;
        processingError = error == null ? null : error.substring(0, Math.min(error.length(), 2000));
    }

    public void resetProcessing(ImageFilter newFilter, String newCorners, Rotation newRotation) {
        if (newFilter != null) filter = newFilter;
        if (newCorners != null) corners = newCorners;
        if (newRotation != null) rotation = newRotation.degrees();
        status = ProcessingStatus.PENDING;
        processingError = null;
    }

    private void applyFields(ExpenseUpdate u) {
        merchant = u.merchant();
        category = u.category();
        expenseDate = u.expenseDate();
        amountTotal = u.amountTotal();
        amountVat = u.amountVat();
        currency = u.currency();
        city = u.city();
        country = u.country();
        address = u.address();
        paymentMethod = u.paymentMethod();
        description = u.description();
    }

    // --- Accesseurs ---

    public UUID getId() { return id; }
    public UUID getOwnerId() { return ownerId; }

    public boolean isOwnedBy(UUID accountId) {
        return ownerId != null && ownerId.equals(accountId);
    }
    public String getMerchant() { return merchant; }
    public void setMerchant(String merchant) { this.merchant = merchant; }
    public Category getCategory() { return category; }
    public void setCategory(Category category) { this.category = category; }
    public LocalDate getExpenseDate() { return expenseDate; }
    public void setExpenseDate(LocalDate expenseDate) { this.expenseDate = expenseDate; }
    public BigDecimal getAmountTotal() { return amountTotal; }
    public void setAmountTotal(BigDecimal amountTotal) { this.amountTotal = amountTotal; }
    public BigDecimal getAmountVat() { return amountVat; }
    public void setAmountVat(BigDecimal amountVat) { this.amountVat = amountVat; }
    public String getCurrency() { return currency; }
    public void setCurrency(String currency) { this.currency = currency; }
    public String getCity() { return city; }
    public void setCity(String city) { this.city = city; }
    public String getCountry() { return country; }
    public void setCountry(String country) { this.country = country; }
    public String getAddress() { return address; }
    public void setAddress(String address) { this.address = address; }
    public String getPaymentMethod() { return paymentMethod; }
    public void setPaymentMethod(String paymentMethod) { this.paymentMethod = paymentMethod; }
    public String getDescription() { return description; }
    public void setDescription(String description) { this.description = description; }
    public boolean isUserEdited() { return userEdited; }
    public void setUserEdited(boolean userEdited) { this.userEdited = userEdited; }
    public String getOriginalFile() { return originalFile; }
    public void setOriginalFile(String originalFile) { this.originalFile = originalFile; }
    public String getOriginalContentType() { return originalContentType; }
    public void setOriginalContentType(String originalContentType) { this.originalContentType = originalContentType; }
    public String getProcessedFile() { return processedFile; }
    public void setProcessedFile(String processedFile) { this.processedFile = processedFile; }
    public ImageFilter getFilter() { return filter; }
    public void setFilter(ImageFilter filter) { this.filter = filter; }
    public boolean isCropped() { return cropped; }
    public String getCorners() { return corners; }

    public Rotation getRotation() { return Rotation.ofDegrees(rotation); }
    public void setRotation(Rotation rotation) { this.rotation = rotation.degrees(); }
    public void setCorners(String corners) { this.corners = corners; }
    public void setCropped(boolean cropped) { this.cropped = cropped; }
    public Long getSizeBytes() { return sizeBytes; }
    public void setSizeBytes(Long sizeBytes) { this.sizeBytes = sizeBytes; }
    public ProcessingStatus getStatus() { return status; }
    public void setStatus(ProcessingStatus status) { this.status = status; }
    public String getProcessingError() { return processingError; }
    public void setProcessingError(String processingError) { this.processingError = processingError; }
    public String getExtractionRaw() { return extractionRaw; }
    public void setExtractionRaw(String extractionRaw) { this.extractionRaw = extractionRaw; }
    public Instant getCreatedAt() { return createdAt; }
    public Instant getUpdatedAt() { return updatedAt; }
    public boolean isDeleted() { return deleted; }
    public void setDeleted(boolean deleted) { this.deleted = deleted; }
}
