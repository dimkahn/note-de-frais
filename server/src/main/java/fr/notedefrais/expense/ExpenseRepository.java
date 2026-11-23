package fr.notedefrais.expense;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

public interface ExpenseRepository extends JpaRepository<Expense, UUID>, JpaSpecificationExecutor<Expense> {

    List<Expense> findByOwnerIdAndUpdatedAtAfterOrderByUpdatedAtAsc(UUID ownerId, Instant since);

    List<Expense> findByStatusAndDeletedFalse(ProcessingStatus status);
}
