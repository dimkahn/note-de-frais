package fr.notedefrais.account;

import java.util.List;
import java.util.UUID;

/** Espace en ligne d'un compte : usage cumulé de toutes ses données, borné par son offre. */
public final class Quota {

    private final List<StorageUsage> usages;
    private final AccountLimits limits;

    public Quota(List<StorageUsage> usages, AccountLimits limits) {
        this.usages = List.copyOf(usages);
        this.limits = limits;
    }

    public long usedBytes(UUID ownerId) {
        return usages.stream().mapToLong(usage -> usage.usedBytes(ownerId)).sum();
    }

    /** @throws QuotaExceededException si {@code incomingBytes} de plus dépasseraient l'offre (égalité acceptée) */
    public void ensureRoomFor(UUID ownerId, long incomingBytes) {
        long used = usedBytes(ownerId);
        long quota = limits.limitsOf(ownerId).quotaBytes();
        if (used + incomingBytes > quota) throw new QuotaExceededException(used, quota);
    }
}
