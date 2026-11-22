package fr.notedefrais.extraction;

/** Résultat d'une extraction : champs normalisés + réponse brute (traçabilité). */
public record ReceiptExtraction(ReceiptFields fields, String raw) {}
