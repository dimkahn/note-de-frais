package fr.notedefrais.document;

import fr.notedefrais.account.StorageUsage;
import java.util.List;
import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

public interface DocumentPageRepository extends JpaRepository<DocumentPage, UUID>, StorageUsage {

    List<DocumentPage> findByDocumentId(UUID documentId);

    /** Pages non retirées des documents non supprimés du compte. */
    @Override
    @Query("""
            select coalesce(sum(p.sizeBytes), 0) from DocumentPage p
            where p.ownerId = :ownerId and p.removed = false
              and p.documentId in (select d.id from Document d where d.deleted = false)""")
    long usedBytes(UUID ownerId);
}
