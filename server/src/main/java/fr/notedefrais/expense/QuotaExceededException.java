package fr.notedefrais.expense;

/** L'envoi ferait dépasser l'espace en ligne de l'offre du compte ; rien n'a été stocké. */
public class QuotaExceededException extends RuntimeException {

    private final long usedBytes;
    private final long quotaBytes;

    public QuotaExceededException(long usedBytes, long quotaBytes) {
        super("Espace de stockage de l'offre dépassé (" + usedBytes + " octets utilisés sur " + quotaBytes + ")");
        this.usedBytes = usedBytes;
        this.quotaBytes = quotaBytes;
    }

    public long usedBytes() { return usedBytes; }
    public long quotaBytes() { return quotaBytes; }
}
