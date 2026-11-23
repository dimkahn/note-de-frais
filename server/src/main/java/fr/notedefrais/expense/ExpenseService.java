package fr.notedefrais.expense;

import fr.notedefrais.account.Quota;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.expense.ExpenseSpecs.Criteria;
import fr.notedefrais.imaging.Quad;
import fr.notedefrais.storage.FileStorage;
import fr.notedefrais.storage.StorageException;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

@Service
public class ExpenseService {

    private static final Logger log = LoggerFactory.getLogger(ExpenseService.class);
    private static final Sort NEWEST_FIRST = Sort.by(Sort.Order.desc("expenseDate"), Sort.Order.desc("createdAt"));

    private final ExpenseRepository repository;
    private final FileStorage storage;
    private final ProcessingQueue queue;
    private final Quota quota;

    public ExpenseService(ExpenseRepository repository, FileStorage storage, ProcessingQueue queue,
                          Quota quota) {
        this.repository = repository;
        this.storage = storage;
        this.queue = queue;
        this.quota = quota;
    }

    /**
     * Enregistre un justificatif. Idempotent : un second envoi avec le même identifiant
     * (reprise de synchronisation) renvoie la dépense existante sans toucher à l'original.
     * Un identifiant déjà pris par un autre compte est traité comme introuvable.
     *
     * @throws QuotaExceededException si l'original ferait dépasser l'espace de l'offre (rien n'est stocké)
     */
    public Expense register(UUID ownerId, UUID id, byte[] original, String contentType, ImageFilter filter, Quad corners) {
        var existing = repository.findById(id);
        if (existing.isPresent()) {
            if (!existing.get().isOwnedBy(ownerId)) throw new ExpenseNotFoundException(id);
            return existing.get();
        }

        quota.ensureRoomFor(ownerId, original.length);

        var expense = new Expense(id, ownerId);
        expense.setOriginalFile(storage.saveOriginal(id, original, extensionOf(contentType)));
        expense.setSizeBytes((long) original.length);
        expense.setOriginalContentType(contentType);
        expense.setFilter(filter == null ? ImageFilter.ENHANCE : filter);
        expense.setCorners(corners == null ? null : corners.format());
        Expense saved = repository.save(expense);
        queue.submit(id);
        return saved;
    }

    /** Relance les traitements interrompus (redémarrage du serveur pendant un traitement). */
    @EventListener(ApplicationReadyEvent.class)
    public void resumePending() {
        repository.findByStatusAndDeletedFalse(ProcessingStatus.PENDING)
                .forEach(e -> queue.submit(e.getId()));
    }

    /**
     * Calcule, depuis les fichiers, la taille des dépenses enregistrées avant les quotas. Une dépense
     * aux fichiers illisibles reste sans taille (non comptée) et sera retentée au prochain démarrage.
     */
    @EventListener(ApplicationReadyEvent.class)
    public void backfillSizes() {
        for (Expense expense : repository.findBySizeBytesIsNull()) {
            try {
                repository.recordMissingSize(expense.getId(), sizeOfFiles(expense));
            } catch (StorageException e) {
                log.warn("Taille non calculable pour la dépense {}", expense.getId(), e);
            }
        }
    }

    public Expense get(UUID ownerId, UUID id) {
        return repository.findById(id).filter(e -> !e.isDeleted() && e.isOwnedBy(ownerId))
                .orElseThrow(() -> new ExpenseNotFoundException(id));
    }

    public List<Expense> search(UUID ownerId, Criteria criteria) {
        return repository.findAll(ExpenseSpecs.ownedBy(ownerId).and(ExpenseSpecs.matching(criteria)), NEWEST_FIRST);
    }

    public List<ExpenseSummary.Group> summary(UUID ownerId, Criteria criteria, ExpenseSummary.GroupBy groupBy) {
        return ExpenseSummary.group(search(ownerId, criteria), groupBy);
    }

    /** Toutes les dépenses du compte modifiées (y compris supprimées) depuis {@code since}, pour la synchro. */
    public List<Expense> changesSince(UUID ownerId, Instant since) {
        return repository.findByOwnerIdAndUpdatedAtAfterOrderByUpdatedAtAsc(ownerId, since);
    }

    public Expense update(UUID ownerId, UUID id, ExpenseUpdate update) {
        Expense expense = get(ownerId, id);
        expense.applyManualEdit(update);
        return repository.save(expense);
    }

    /** Relance le traitement depuis l'original (autre filtre et/ou autres coins ; null = inchangé). */
    public Expense reprocess(UUID ownerId, UUID id, ImageFilter filter, Quad corners) {
        Expense expense = get(ownerId, id);
        expense.resetProcessing(filter, corners == null ? null : corners.format());
        Expense saved = repository.save(expense);
        queue.submit(id);
        return saved;
    }

    public void delete(UUID ownerId, UUID id) {
        Expense expense = get(ownerId, id);
        expense.setDeleted(true);
        repository.save(expense);
    }

    public byte[] original(UUID ownerId, UUID id) {
        return storage.read(id, get(ownerId, id).getOriginalFile());
    }

    public byte[] processed(UUID ownerId, UUID id) {
        Expense e = get(ownerId, id);
        if (e.getProcessedFile() == null) throw new ExpenseNotFoundException(id);
        return storage.read(id, e.getProcessedFile());
    }

    private long sizeOfFiles(Expense e) {
        long size = storage.read(e.getId(), e.getOriginalFile()).length;
        if (e.getProcessedFile() != null) size += storage.read(e.getId(), e.getProcessedFile()).length;
        return size;
    }

    private static String extensionOf(String contentType) {
        if (contentType == null) return "bin";
        return switch (contentType.toLowerCase(Locale.ROOT)) {
            case "image/jpeg", "image/jpg" -> "jpg";
            case "image/png" -> "png";
            case "image/webp" -> "webp";
            case "image/heic" -> "heic";
            default -> "bin";
        };
    }
}
