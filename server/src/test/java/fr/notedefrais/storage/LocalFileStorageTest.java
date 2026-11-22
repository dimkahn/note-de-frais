package fr.notedefrais.storage;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.nio.file.Path;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class LocalFileStorageTest {

    @TempDir
    Path root;

    @Test
    void conserve_l_original_a_l_identique() {
        var storage = new LocalFileStorage(root);
        var id = UUID.randomUUID();
        byte[] bytes = {1, 2, 3};

        String name = storage.saveOriginal(id, bytes, "jpg");

        assertThat(storage.read(id, name)).containsExactly(1, 2, 3);
    }

    @Test
    void refuse_d_ecraser_un_original_existant() {
        var storage = new LocalFileStorage(root);
        var id = UUID.randomUUID();
        storage.saveOriginal(id, new byte[]{1}, "jpg");

        assertThatThrownBy(() -> storage.saveOriginal(id, new byte[]{9}, "jpg"))
                .isInstanceOf(OriginalAlreadyExistsException.class);
        assertThat(storage.read(id, "original.jpg")).containsExactly(1);
    }

    @Test
    void la_version_traitee_peut_etre_regeneree() {
        var storage = new LocalFileStorage(root);
        var id = UUID.randomUUID();
        storage.saveProcessed(id, new byte[]{1});

        String name = storage.saveProcessed(id, new byte[]{2});

        assertThat(storage.read(id, name)).containsExactly(2);
    }

    @Test
    void refuse_un_nom_de_fichier_sortant_du_dossier() {
        var storage = new LocalFileStorage(root);

        assertThatThrownBy(() -> storage.read(UUID.randomUUID(), "../../etc/passwd"))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void normalise_l_extension() {
        var storage = new LocalFileStorage(root);

        String name = storage.saveOriginal(UUID.randomUUID(), new byte[]{1}, "../JPEG");

        assertThat(name).isEqualTo("original.jpeg");
    }
}
