package fr.notedefrais.expense;

public enum ProcessingStatus {
    /** Original reçu, traitement en cours. */
    PENDING,
    /** Image recadrée/améliorée et informations extraites. */
    DONE,
    /** Image traitée, mais l'extraction a échoué (champs à saisir à la main). */
    EXTRACTION_FAILED,
    /** Le traitement d'image a échoué ; l'original reste disponible. */
    FAILED
}
