package fr.notedefrais.account;

import java.util.UUID;
import org.springframework.data.jpa.repository.JpaRepository;

public interface DeviceKeyRepository extends JpaRepository<DeviceKey, String> {

    void deleteByAccountId(UUID accountId);
}
