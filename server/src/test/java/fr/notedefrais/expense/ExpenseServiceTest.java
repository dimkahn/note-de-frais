package fr.notedefrais.expense;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import fr.notedefrais.extraction.ExtractionException;
import fr.notedefrais.extraction.ReceiptExtraction;
import fr.notedefrais.extraction.ReceiptExtractor;
import fr.notedefrais.extraction.ReceiptFields;
import fr.notedefrais.imaging.ImageProcessingException;
import fr.notedefrais.imaging.ImageProcessor;
import fr.notedefrais.imaging.ProcessedImage;
import fr.notedefrais.imaging.Quad;
import fr.notedefrais.storage.LocalFileStorage;
import java.math.BigDecimal;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

@DataJpaTest
@Transactional(propagation = Propagation.NOT_SUPPORTED)
class ExpenseServiceTest {

    static final byte[] PHOTO = {10, 20, 30};
    static final byte[] PROCESSED = {99};
    static final ReceiptFields BISTROT = new ReceiptFields("Le Bistrot", Category.RESTAURANT,
            LocalDate.of(2026, 3, 10), new BigDecimal("42.50"), new BigDecimal("3.86"), "EUR",
            "Paris", "FR", "1 rue de Rivoli", "CB", "Déjeuner");

    @Autowired
    ExpenseRepository repository;
    @TempDir
    Path storageDir;

    LocalFileStorage storage;
    FakeExtractor extractor;
    FakeImageProcessor imageProcessor;
    List<UUID> queued;
    ExpenseService service;
    ExpenseProcessor processor;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        storage = new LocalFileStorage(storageDir);
        extractor = new FakeExtractor();
        imageProcessor = new FakeImageProcessor();
        queued = new ArrayList<>();
        processor = new ExpenseProcessor(repository, storage, imageProcessor, extractor);
        service = new ExpenseService(repository, storage, queued::add);
    }

    @Test
    void l_enregistrement_conserve_l_original_et_planifie_le_traitement() {
        var id = UUID.randomUUID();

        Expense e = service.register(id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);

        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.PENDING);
        assertThat(storage.read(id, e.getOriginalFile())).containsExactly(PHOTO);
        assertThat(queued).containsExactly(id);
    }

    @Test
    void l_enregistrement_est_idempotent_et_ne_touche_pas_l_original() {
        var id = UUID.randomUUID();
        service.register(id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);

        Expense again = service.register(id, new byte[]{1}, "image/jpeg", ImageFilter.NONE, null);

        assertThat(storage.read(id, again.getOriginalFile())).containsExactly(PHOTO);
        assertThat(again.getFilter()).isEqualTo(ImageFilter.ENHANCE);
        assertThat(queued).containsExactly(id);
    }

    @Test
    void le_traitement_stocke_l_image_traitee_et_les_informations_extraites() {
        var id = register();

        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.DONE);
        assertThat(e.isCropped()).isTrue();
        assertThat(storage.read(id, e.getProcessedFile())).containsExactly(PROCESSED);
        assertThat(e.getMerchant()).isEqualTo("Le Bistrot");
        assertThat(e.getAmountTotal()).isEqualByComparingTo("42.50");
        assertThat(e.getCity()).isEqualTo("Paris");
        assertThat(extractor.receivedImages).containsExactly(PROCESSED);
    }

    @Test
    void le_traitement_part_toujours_de_l_original() {
        var id = register();

        processor.process(id);
        processor.process(id);

        assertThat(imageProcessor.inputs).allSatisfy(input -> assertThat(input).containsExactly(PHOTO));
    }

    @Test
    void un_echec_d_extraction_garde_l_image_traitee() {
        var id = register();
        extractor.failure = new ExtractionException("indisponible");

        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.EXTRACTION_FAILED);
        assertThat(e.getProcessingError()).contains("indisponible");
        assertThat(e.getProcessedFile()).isNotNull();
    }

    @Test
    void un_echec_du_traitement_d_image_garde_l_original() {
        var id = register();
        imageProcessor.failure = new ImageProcessingException("illisible");

        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.FAILED);
        assertThat(storage.read(id, e.getOriginalFile())).containsExactly(PHOTO);
    }

    @Test
    void une_correction_manuelle_n_est_pas_ecrasee_par_une_nouvelle_extraction() {
        var id = register();
        processor.process(id);
        service.update(id, new ExpenseUpdate("Bistrot Corrigé", Category.RESTAURANT, LocalDate.of(2026, 3, 10),
                new BigDecimal("45.00"), null, "EUR", "Paris", "FR", null, "CB", "Repas équipe"));

        service.reprocess(id, ImageFilter.SCAN_BW, null);
        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.isUserEdited()).isTrue();
        assertThat(e.getMerchant()).isEqualTo("Bistrot Corrigé");
        assertThat(e.getAmountTotal()).isEqualByComparingTo("45.00");
        assertThat(e.getFilter()).isEqualTo(ImageFilter.SCAN_BW);
        assertThat(imageProcessor.filters).containsExactly(ImageFilter.ENHANCE, ImageFilter.SCAN_BW);
    }

    @Test
    void les_coins_choisis_a_la_capture_sont_conserves_et_reutilises() {
        var id = UUID.randomUUID();
        var quad = Quad.parse("0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9");
        service.register(id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, quad);

        processor.process(id);
        service.reprocess(id, ImageFilter.SCAN_BW, null);
        processor.process(id);

        assertThat(repository.findById(id).orElseThrow().getCorners()).isEqualTo(quad.format());
        assertThat(imageProcessor.corners).containsExactly(quad, quad);
    }

    @Test
    void de_nouveaux_coins_au_retraitement_remplacent_les_precedents() {
        var id = register();
        var quad = Quad.parse("0.2,0.2,0.8,0.2,0.8,0.8,0.2,0.8");

        service.reprocess(id, null, quad);
        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.getCorners()).isEqualTo(quad.format());
        assertThat(e.getFilter()).isEqualTo(ImageFilter.ENHANCE);
        assertThat(imageProcessor.corners).containsExactly(quad);
    }

    @Test
    void la_suppression_est_logique_et_visible_dans_les_changements() {
        var id = register();
        Instant before = Instant.now().minusSeconds(1);

        service.delete(id);

        assertThat(repository.findById(id)).get().extracting(Expense::isDeleted).isEqualTo(true);
        assertThat(service.changesSince(before)).extracting(Expense::getId).containsExactly(id);
        assertThatThrownBy(() -> service.get(id)).isInstanceOf(ExpenseNotFoundException.class);
    }

    @Test
    void au_demarrage_les_traitements_interrompus_sont_relances() {
        var interrupted = register();
        var done = register();
        processor.process(done);
        queued.clear();

        service.resumePending();

        assertThat(queued).containsExactly(interrupted);
    }

    @Test
    void une_depense_inconnue_leve_une_erreur_explicite() {
        assertThatThrownBy(() -> service.get(UUID.randomUUID())).isInstanceOf(ExpenseNotFoundException.class);
    }

    private UUID register() {
        var id = UUID.randomUUID();
        service.register(id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);
        return id;
    }

    static final class FakeExtractor implements ReceiptExtractor {
        final List<byte[]> receivedImages = new ArrayList<>();
        ExtractionException failure;

        @Override
        public ReceiptExtraction extract(byte[] jpeg) {
            receivedImages.add(jpeg);
            if (failure != null) throw failure;
            return new ReceiptExtraction(BISTROT, "{\"merchant\":\"Le Bistrot\"}");
        }
    }

    static final class FakeImageProcessor implements ImageProcessor {
        final List<byte[]> inputs = new ArrayList<>();
        final List<ImageFilter> filters = new ArrayList<>();
        final List<Quad> corners = new ArrayList<>();
        ImageProcessingException failure;

        @Override
        public ProcessedImage process(byte[] original, ImageFilter filter, Quad quad) {
            inputs.add(original);
            filters.add(filter);
            corners.add(quad);
            if (failure != null) throw failure;
            return new ProcessedImage(PROCESSED, true);
        }
    }
}
