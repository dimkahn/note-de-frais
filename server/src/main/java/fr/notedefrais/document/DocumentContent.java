package fr.notedefrais.document;

import java.util.List;

/** Un document et ses pages visibles (reçues, non retirées), dans l'ordre voulu. */
public record DocumentContent(Document document, List<DocumentPage> pages) {}
