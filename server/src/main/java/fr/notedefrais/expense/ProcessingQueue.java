package fr.notedefrais.expense;

import java.util.UUID;

/** Planifie le traitement (recadrage, filtre, extraction) d'une dépense. */
@FunctionalInterface
public interface ProcessingQueue {
    void submit(UUID expenseId);
}
