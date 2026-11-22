package fr.notedefrais.expense;

import java.util.UUID;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;

/** Traitement en tâche de fond (threads virtuels) : l'upload répond immédiatement. */
@Component
public class AsyncProcessingQueue implements ProcessingQueue {

    private final ExpenseProcessor processor;

    public AsyncProcessingQueue(ExpenseProcessor processor) {
        this.processor = processor;
    }

    @Async
    @Override
    public void submit(UUID expenseId) {
        processor.process(expenseId);
    }
}
