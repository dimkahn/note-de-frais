package fr.notedefrais.document;

import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DocumentRepository extends JpaRepository<Document, UUID> {

    List<Document> findByOwnerIdAndUpdatedAtAfterOrderByUpdatedAtAsc(UUID ownerId, Instant since);
}
