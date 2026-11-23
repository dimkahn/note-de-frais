package fr.notedefrais.account;

import java.util.UUID;

/** Place occupée en ligne par une sorte de données d'un compte (dépenses, documents…). */
public interface StorageUsage {
    long usedBytes(UUID ownerId);
}
