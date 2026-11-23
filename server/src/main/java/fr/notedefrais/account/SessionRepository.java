package fr.notedefrais.account;

import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface SessionRepository extends JpaRepository<Session, String> {

    void deleteByAccountId(UUID accountId);
}
