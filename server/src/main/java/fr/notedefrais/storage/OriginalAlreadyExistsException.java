package fr.notedefrais.storage;

import java.util.UUID;

public class OriginalAlreadyExistsException extends RuntimeException {
    public OriginalAlreadyExistsException(UUID expenseId) {
        super("L'original de la dépense " + expenseId + " existe déjà et ne peut pas être remplacé");
    }
}
