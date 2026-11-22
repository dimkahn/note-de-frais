package fr.notedefrais.expense;

import fr.notedefrais.extraction.ExtractionException;
import fr.notedefrais.extraction.ReceiptExtraction;
import fr.notedefrais.extraction.ReceiptExtractor;
import fr.notedefrais.extraction.ReceiptFields;
import fr.notedefrais.imaging.ImageProcessor;
import fr.notedefrais.imaging.ProcessedImage;
import fr.notedefrais.storage.FileStorage;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

/**
 * Traite une dépense à partir de son original : recadrage + filtre, puis extraction.
 * Aucune transaction n'est ouverte pendant les étapes longues (image, appel Claude).
 */
@Component
public class ExpenseProcessor {

    private static final Logger log = LoggerFactory.getLogger(ExpenseProcessor.class);

    private final ExpenseRepository repository;
    private final FileStorage storage;
    private final ImageProcessor imageProcessor;
    private final ReceiptExtractor extractor;

    public ExpenseProcessor(ExpenseRepository repository, FileStorage storage,
                            ImageProcessor imageProcessor, ReceiptExtractor extractor) {
        this.repository = repository;
        this.storage = storage;
        this.imageProcessor = imageProcessor;
        this.extractor = extractor;
    }

    public void process(UUID id) {
        Expense expense = repository.findById(id).filter(e -> !e.isDeleted()).orElse(null);
        if (expense == null) return;

        ProcessedImage image;
        String processedFile;
        try {
            byte[] original = storage.read(id, expense.getOriginalFile());
            image = imageProcessor.process(original, expense.getFilter());
            processedFile = storage.saveProcessed(id, image.jpeg());
        } catch (RuntimeException e) {
            log.warn("Traitement d'image impossible pour {}", id, e);
            save(id, fresh -> fresh.markFailed(ProcessingStatus.FAILED, e.getMessage()));
            return;
        }

        ReceiptExtraction extraction;
        try {
            extraction = extractor.extract(image.jpeg());
        } catch (ExtractionException e) {
            log.warn("Extraction impossible pour {} : {}", id, e.getMessage());
            save(id, fresh -> {
                fresh.attachProcessedImage(processedFile, image.cropped());
                fresh.markFailed(ProcessingStatus.EXTRACTION_FAILED, e.getMessage());
            });
            return;
        }

        save(id, fresh -> {
            fresh.attachProcessedImage(processedFile, image.cropped());
            fresh.applyExtraction(toUpdate(extraction.fields()), extraction.raw());
        });
    }

    /** Recharge l'entité avant écriture pour ne pas écraser une modification faite entre-temps. */
    private void save(UUID id, java.util.function.Consumer<Expense> change) {
        repository.findById(id).ifPresent(fresh -> {
            change.accept(fresh);
            repository.save(fresh);
        });
    }

    private static ExpenseUpdate toUpdate(ReceiptFields f) {
        return new ExpenseUpdate(f.merchant(), f.category(), f.expenseDate(), f.amountTotal(), f.amountVat(),
                f.currency(), f.city(), f.country(), f.address(), f.paymentMethod(), f.description());
    }
}
