package fr.notedefrais.expense;

import fr.notedefrais.expense.ExpenseSpecs.Criteria;
import fr.notedefrais.storage.FileStorage;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.data.domain.Sort;
import org.springframework.stereotype.Service;

@Service
public class ExpenseService {

    private static final Sort NEWEST_FIRST = Sort.by(Sort.Order.desc("expenseDate"), Sort.Order.desc("createdAt"));

    private final ExpenseRepository repository;
    private final FileStorage storage;
    private final ProcessingQueue queue;

    public ExpenseService(ExpenseRepository repository, FileStorage storage, ProcessingQueue queue) {
        this.repository = repository;
        this.storage = storage;
        this.queue = queue;
    }

    /**
     * Enregistre un justificatif. Idempotent : un second envoi avec le même identifiant
     * (reprise de synchronisation) renvoie la dépense existante sans toucher à l'original.
     */
    public Expense register(UUID id, byte[] original, String contentType, ImageFilter filter) {
        var existing = repository.findById(id);
        if (existing.isPresent()) return existing.get();

        var expense = new Expense(id);
        expense.setOriginalFile(storage.saveOriginal(id, original, extensionOf(contentType)));
        expense.setOriginalContentType(contentType);
        expense.setFilter(filter == null ? ImageFilter.ENHANCE : filter);
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

    public Expense get(UUID id) {
        return repository.findById(id).filter(e -> !e.isDeleted())
                .orElseThrow(() -> new ExpenseNotFoundException(id));
    }

    public List<Expense> search(Criteria criteria) {
        return repository.findAll(ExpenseSpecs.matching(criteria), NEWEST_FIRST);
    }

    public List<ExpenseSummary.Group> summary(Criteria criteria, ExpenseSummary.GroupBy groupBy) {
        return ExpenseSummary.group(search(criteria), groupBy);
    }

    /** Toutes les dépenses modifiées (y compris supprimées) depuis {@code since}, pour la synchro. */
    public List<Expense> changesSince(Instant since) {
        return repository.findByUpdatedAtAfterOrderByUpdatedAtAsc(since);
    }

    public Expense update(UUID id, ExpenseUpdate update) {
        Expense expense = get(id);
        expense.applyManualEdit(update);
        return repository.save(expense);
    }

    /** Relance le traitement depuis l'original avec un autre filtre. */
    public Expense reprocess(UUID id, ImageFilter filter) {
        Expense expense = get(id);
        expense.resetProcessing(filter);
        Expense saved = repository.save(expense);
        queue.submit(id);
        return saved;
    }

    public void delete(UUID id) {
        Expense expense = get(id);
        expense.setDeleted(true);
        repository.save(expense);
    }

    public byte[] original(UUID id) {
        return storage.read(id, get(id).getOriginalFile());
    }

    public byte[] processed(UUID id) {
        Expense e = get(id);
        if (e.getProcessedFile() == null) throw new ExpenseNotFoundException(id);
        return storage.read(id, e.getProcessedFile());
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
