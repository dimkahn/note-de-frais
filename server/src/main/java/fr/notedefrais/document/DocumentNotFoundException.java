package fr.notedefrais.document;

import java.util.UUID;

/** Document (ou page) inconnu, supprimé ou appartenant à un autre compte : indiscernables (404). */
public class DocumentNotFoundException extends RuntimeException {
    public DocumentNotFoundException(UUID id) {
        super("Document introuvable : " + id);
    }
}
