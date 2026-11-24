package fr.notedefrais.receipt.extraction;

/** Lit les informations d'un justificatif à partir de son image traitée. */
public interface ReceiptExtractor {

    /** @throws ExtractionException si l'extraction est impossible */
    ReceiptExtraction extract(byte[] jpeg);
}
