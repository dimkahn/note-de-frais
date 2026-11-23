package fr.notedefrais.expense;

import fr.notedefrais.account.AccountLimits;
import fr.notedefrais.extraction.ExtractionException;
import fr.notedefrais.extraction.ReceiptExtraction;
import fr.notedefrais.extraction.ReceiptExtractor;
import fr.notedefrais.extraction.ReceiptFields;
import fr.notedefrais.imaging.ImageProcessor;
import fr.notedefrais.imaging.ProcessedImage;
import fr.notedefrais.imaging.Quad;
import fr.notedefrais.storage.FileStorage;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Traite une dépense à partir de son original : recadrage + filtre, puis extraction si l'offre
 * du compte inclut l'analyse IA. La taille stockée (original + rendu) est mise à jour.
 * Aucune transaction n'est ouverte pendant les étapes longues (image, appel Claude).
 */
@Component
public class ExpenseProcessor {

    private static final Logger log = LoggerFactory.getLogger(ExpenseProcessor.class);

    private final ExpenseRepository repository;
    private final FileStorage storage;
    private final ImageProcessor imageProcessor;
    private final ReceiptExtractor extractor;
    private final AccountLimits limits;

    public ExpenseProcessor(ExpenseRepository repository, FileStorage storage,
                            ImageProcessor imageProcessor, ReceiptExtractor extractor, AccountLimits limits) {
        this.repository = repository;
        this.storage = storage;
        this.imageProcessor = imageProcessor;
        this.extractor = extractor;
        this.limits = limits;
    }

    public void process(UUID id) {
        Expense expense = repository.findById(id).filter(e -> !e.isDeleted()).orElse(null);
        if (expense == null) return;

        Rendering rendering = render(expense);
        if (rendering == null) return;

        if (!aiAnalysisIncluded(expense)) {
            save(id, fresh -> {
                rendering.attachTo(fresh);
                fresh.markAnalysisNotIncluded();
            });
            return;
        }
        extract(id, rendering);
    }

    /** Recadrage + filtre depuis l'original ; null (et dépense en échec) si l'image est inexploitable. */
    private Rendering render(Expense expense) {
        UUID id = expense.getId();
        try {
            byte[] original = storage.read(id, expense.getOriginalFile());
            Quad corners = expense.getCorners() == null ? null : Quad.parse(expense.getCorners());
            ProcessedImage image = imageProcessor.process(original, expense.getFilter(), corners);
            String file = storage.saveProcessed(id, image.jpeg());
            return new Rendering(image, file, (long) original.length + image.jpeg().length);
        } catch (RuntimeException e) {
            log.warn("Traitement d'image impossible pour {}", id, e);
            save(id, fresh -> fresh.markFailed(ProcessingStatus.FAILED, e.getMessage()));
            return null;
        }
    }

    private void extract(UUID id, Rendering rendering) {
        ReceiptExtraction extraction;
        try {
            extraction = extractor.extract(rendering.image().jpeg());
        } catch (ExtractionException e) {
            log.warn("Extraction impossible pour {} : {}", id, e.getMessage());
            save(id, fresh -> {
                rendering.attachTo(fresh);
                fresh.markFailed(ProcessingStatus.EXTRACTION_FAILED, e.getMessage());
            });
            return;
        }

        save(id, fresh -> {
            rendering.attachTo(fresh);
            fresh.applyExtraction(toUpdate(extraction.fields()), extraction.raw());
        });
    }

    /** Les dépenses sans propriétaire (antérieures aux comptes) ne sont pas analysées. */
    private boolean aiAnalysisIncluded(Expense expense) {
        return expense.getOwnerId() != null && limits.limitsOf(expense.getOwnerId()).aiAnalysis();
    }

    /** Recharge l'entité avant écriture pour ne pas écraser une modification faite entre-temps. */
    private void save(UUID id, java.util.function.Consumer<Expense> change) {
        repository.findById(id).ifPresent(fresh -> {
            change.accept(fresh);
            repository.save(fresh);
        });
    }

    /** Rendu enregistré, avec la place totale occupée (original + rendu). */
    private record Rendering(ProcessedImage image, String file, long totalSizeBytes) {
        void attachTo(Expense expense) {
            expense.attachProcessedImage(file, image.cropped(), totalSizeBytes);
        }
    }

    private static ExpenseUpdate toUpdate(ReceiptFields f) {
        return new ExpenseUpdate(f.merchant(), f.category(), f.expenseDate(), f.amountTotal(), f.amountVat(),
                f.currency(), f.city(), f.country(), f.address(), f.paymentMethod(), f.description());
    }
}
