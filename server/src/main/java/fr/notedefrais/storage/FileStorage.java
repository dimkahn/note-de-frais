package fr.notedefrais.storage;

import java.util.UUID;

/** Stockage des justificatifs. Les originaux sont en écriture unique. */
public interface FileStorage {

    /** Enregistre l'original ; échoue s'il existe déjà. Retourne le nom du fichier. */
    String saveOriginal(UUID expenseId, byte[] content, String extension);

    /** Enregistre (ou remplace) la version traitée. Retourne le nom du fichier. */
    String saveProcessed(UUID expenseId, byte[] jpeg);

    byte[] read(UUID expenseId, String fileName);
}
