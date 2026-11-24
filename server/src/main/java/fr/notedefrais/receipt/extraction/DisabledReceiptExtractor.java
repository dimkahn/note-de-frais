package fr.notedefrais.receipt.extraction;

/** Utilisé quand l'extraction est désactivée : les champs restent à saisir manuellement. */
public final class DisabledReceiptExtractor implements ReceiptExtractor {

    @Override
    public ReceiptExtraction extract(byte[] jpeg) {
        throw new ExtractionException("Extraction automatique désactivée (app.claude.enabled=false)");
    }
}
