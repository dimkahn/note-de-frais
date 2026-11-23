package fr.notedefrais.expense;

import fr.notedefrais.account.StorageUsage;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.transaction.annotation.Transactional;

public interface ExpenseRepository extends JpaRepository<Expense, UUID>, JpaSpecificationExecutor<Expense>, StorageUsage {

    List<Expense> findByOwnerIdAndUpdatedAtAfterOrderByUpdatedAtAsc(UUID ownerId, Instant since);

    List<Expense> findByStatusAndDeletedFalse(ProcessingStatus status);

    List<Expense> findBySizeBytesIsNull();

    /** N'écrit que la taille (et seulement si elle manque) : un traitement concurrent n'est jamais écrasé. */
    @Modifying
    @Transactional
    @Query("update Expense e set e.sizeBytes = :sizeBytes where e.id = :id and e.sizeBytes is null")
    int recordMissingSize(UUID id, long sizeBytes);

    /** Place occupée par les dépenses non supprimées du compte (les supprimées ne comptent plus). */
    @Override
    @Query("select coalesce(sum(e.sizeBytes), 0) from Expense e where e.ownerId = :ownerId and e.deleted = false")
    long usedBytes(UUID ownerId);
}
