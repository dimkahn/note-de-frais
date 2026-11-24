package fr.notedefrais.expense;

import fr.notedefrais.receipt.imaging.ImageFilter;
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import fr.notedefrais.account.PlanLimits;
import fr.notedefrais.account.Quota;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.receipt.extraction.ExtractionException;
import fr.notedefrais.receipt.extraction.ReceiptExtraction;
import fr.notedefrais.receipt.extraction.ReceiptExtractor;
import fr.notedefrais.receipt.extraction.ReceiptFields;
import fr.notedefrais.receipt.imaging.ImageProcessingException;
import fr.notedefrais.receipt.imaging.ImageProcessor;
import fr.notedefrais.receipt.imaging.ProcessedImage;
import fr.notedefrais.receipt.imaging.Quad;
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

    static final UUID OWNER = UUID.randomUUID();
    static final UUID STRANGER = UUID.randomUUID();
    static final byte[] PHOTO = {10, 20, 30};
    static final byte[] PROCESSED = {99};
    static final ReceiptFields BISTROT = new ReceiptFields("Le Bistrot", Category.RESTAURANT,
            LocalDate.of(2026, 3, 10), new BigDecimal("42.50"), new BigDecimal("3.86"), "EUR",
            "Paris", "FR", "1 rue de Rivoli", "CB", "Déjeuner");
    static final PlanLimits PREMIUM = new PlanLimits(1_000_000, true);
    static final PlanLimits FREE = new PlanLimits(1_000_000, false);

    @Autowired
    ExpenseRepository repository;
    @TempDir
    Path storageDir;

    LocalFileStorage storage;
    FakeExtractor extractor;
    FakeImageProcessor imageProcessor;
    List<UUID> queued;
    PlanLimits limits;
    Quota quota;
    ExpenseService service;
    ExpenseProcessor processor;

    @BeforeEach
    void setUp() {
        repository.deleteAll();
        storage = new LocalFileStorage(storageDir);
        extractor = new FakeExtractor();
        imageProcessor = new FakeImageProcessor();
        queued = new ArrayList<>();
        limits = PREMIUM;
        processor = new ExpenseProcessor(repository, storage, imageProcessor, extractor, owner -> limits);
        quota = new Quota(List.of(repository), owner -> limits);
        service = new ExpenseService(repository, storage, queued::add, quota);
    }

    @Test
    void l_enregistrement_conserve_l_original_et_planifie_le_traitement() {
        var id = UUID.randomUUID();

        Expense e = service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);

        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.PENDING);
        assertThat(storage.read(id, e.getOriginalFile())).containsExactly(PHOTO);
        assertThat(queued).containsExactly(id);
    }

    @Test
    void l_enregistrement_est_idempotent_et_ne_touche_pas_l_original() {
        var id = UUID.randomUUID();
        service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);

        Expense again = service.register(OWNER, id, new byte[]{1}, "image/jpeg", ImageFilter.NONE, null);

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
        service.update(OWNER, id, new ExpenseUpdate("Bistrot Corrigé", Category.RESTAURANT, LocalDate.of(2026, 3, 10),
                new BigDecimal("45.00"), null, "EUR", "Paris", "FR", null, "CB", "Repas équipe"));

        service.reprocess(OWNER, id, ImageFilter.SCAN_BW, null);
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
        service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, quad);

        processor.process(id);
        service.reprocess(OWNER, id, ImageFilter.SCAN_BW, null);
        processor.process(id);

        assertThat(repository.findById(id).orElseThrow().getCorners()).isEqualTo(quad.format());
        assertThat(imageProcessor.corners).containsExactly(quad, quad);
    }

    @Test
    void de_nouveaux_coins_au_retraitement_remplacent_les_precedents() {
        var id = register();
        var quad = Quad.parse("0.2,0.2,0.8,0.2,0.8,0.8,0.2,0.8");

        service.reprocess(OWNER, id, null, quad);
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

        service.delete(OWNER, id);

        assertThat(repository.findById(id)).get().extracting(Expense::isDeleted).isEqualTo(true);
        assertThat(service.changesSince(OWNER, before)).extracting(Expense::getId).containsExactly(id);
        assertThatThrownBy(() -> service.get(OWNER, id)).isInstanceOf(ExpenseNotFoundException.class);
    }

    @Test
    void la_depense_enregistree_appartient_au_compte_qui_l_envoie() {
        var id = register();

        assertThat(repository.findById(id)).get().extracting(Expense::getOwnerId).isEqualTo(OWNER);
    }

    @Test
    void un_compte_ne_voit_pas_la_depense_d_un_autre() {
        var id = register();

        assertThatThrownBy(() -> service.get(STRANGER, id)).isInstanceOf(ExpenseNotFoundException.class);
        assertThatThrownBy(() -> service.original(STRANGER, id)).isInstanceOf(ExpenseNotFoundException.class);
    }

    @Test
    void un_compte_ne_telecharge_pas_l_image_traitee_d_un_autre() {
        var id = register();
        processor.process(id);

        assertThatThrownBy(() -> service.processed(STRANGER, id)).isInstanceOf(ExpenseNotFoundException.class);
    }

    @Test
    void un_compte_ne_modifie_ni_ne_retraite_la_depense_d_un_autre() {
        var id = register();
        var edit = new ExpenseUpdate("Pirate", null, null, null, null, null, null, null, null, null, null);

        assertThatThrownBy(() -> service.update(STRANGER, id, edit)).isInstanceOf(ExpenseNotFoundException.class);
        assertThatThrownBy(() -> service.reprocess(STRANGER, id, ImageFilter.NONE, null))
                .isInstanceOf(ExpenseNotFoundException.class);
        assertThat(repository.findById(id)).get().extracting(Expense::getMerchant).isNull();
    }

    @Test
    void un_compte_ne_supprime_pas_la_depense_d_un_autre() {
        var id = register();

        assertThatThrownBy(() -> service.delete(STRANGER, id)).isInstanceOf(ExpenseNotFoundException.class);
        assertThat(repository.findById(id)).get().extracting(Expense::isDeleted).isEqualTo(false);
    }

    @Test
    void la_recherche_et_les_changements_ne_renvoient_que_les_depenses_du_compte() {
        Instant before = Instant.now().minusSeconds(1);
        var mine = register();
        service.register(STRANGER, UUID.randomUUID(), PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);
        var all = new ExpenseSpecs.Criteria(null, null, null, null, null, null, null);

        assertThat(service.search(OWNER, all)).extracting(Expense::getId).containsExactly(mine);
        assertThat(service.changesSince(OWNER, before)).extracting(Expense::getId).containsExactly(mine);
        assertThat(service.summary(OWNER, all, ExpenseSummary.GroupBy.CATEGORY))
                .extracting(ExpenseSummary.Group::count).containsExactly(1L);
    }

    @Test
    void un_identifiant_deja_pris_par_un_autre_compte_est_refuse_sans_toucher_a_sa_depense() {
        var id = register();

        assertThatThrownBy(() -> service.register(STRANGER, id, new byte[]{1}, "image/jpeg", ImageFilter.NONE, null))
                .isInstanceOf(ExpenseNotFoundException.class);
        Expense e = repository.findById(id).orElseThrow();
        assertThat(e.getOwnerId()).isEqualTo(OWNER);
        assertThat(storage.read(id, e.getOriginalFile())).containsExactly(PHOTO);
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
    void la_taille_de_l_original_est_comptee_des_l_envoi() {
        register();

        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length);
    }

    @Test
    void le_traitement_ajoute_la_taille_du_rendu() {
        var id = register();

        processor.process(id);

        assertThat(repository.findById(id).orElseThrow().getSizeBytes()).isEqualTo(PHOTO.length + PROCESSED.length);
        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length + PROCESSED.length);
    }

    @Test
    void le_retraitement_remplace_la_taille_du_rendu_precedent() {
        var id = register();
        processor.process(id);
        imageProcessor.output = new byte[]{1, 2, 3, 4, 5};

        service.reprocess(OWNER, id, ImageFilter.SCAN_BW, null);
        processor.process(id);

        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length + 5);
    }

    @Test
    void l_usage_d_un_compte_ne_compte_ni_ses_depenses_supprimees_ni_celles_des_autres() {
        var deleted = register();
        register();
        service.register(STRANGER, UUID.randomUUID(), new byte[100], "image/jpeg", ImageFilter.ENHANCE, null);

        service.delete(OWNER, deleted);

        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length);
    }

    @Test
    void un_compte_sans_depense_n_utilise_rien() {
        assertThat(quota.usedBytes(OWNER)).isZero();
    }

    @Test
    void un_envoi_qui_depasserait_le_quota_est_refuse_sans_rien_stocker() {
        limits = new PlanLimits(PHOTO.length + 2, false);
        register();
        var id = UUID.randomUUID();

        var refused = catchThrowableOfType(QuotaExceededException.class,
                () -> service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null));

        assertThat(refused.usedBytes()).isEqualTo(PHOTO.length);
        assertThat(refused.quotaBytes()).isEqualTo(PHOTO.length + 2);
        assertThat(repository.findById(id)).isEmpty();
        assertThat(storageDir.resolve(id.toString())).doesNotExist();
        assertThat(queued).hasSize(1);
    }

    @Test
    void un_envoi_qui_remplit_exactement_le_quota_est_accepte() {
        limits = new PlanLimits(2L * PHOTO.length, false);
        register();

        var id = register();

        assertThat(repository.findById(id)).isPresent();
    }

    @Test
    void le_renvoi_d_une_depense_deja_enregistree_n_est_pas_refuse_pour_quota() {
        limits = new PlanLimits(PHOTO.length, false);
        var id = register();

        Expense again = service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);

        assertThat(again.getId()).isEqualTo(id);
    }

    @Test
    void sans_analyse_ia_incluse_le_rendu_est_produit_sans_appeler_claude() {
        limits = FREE;
        var id = register();

        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(extractor.receivedImages).isEmpty();
        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.NOT_INCLUDED);
        assertThat(storage.read(id, e.getProcessedFile())).containsExactly(PROCESSED);
        assertThat(e.getSizeBytes()).isEqualTo(PHOTO.length + PROCESSED.length);
    }

    @Test
    void sans_analyse_ia_incluse_le_retraitement_garde_les_informations_deja_lues() {
        var id = register();
        processor.process(id);
        limits = FREE;

        service.reprocess(OWNER, id, ImageFilter.SCAN_BW, null);
        processor.process(id);

        Expense e = repository.findById(id).orElseThrow();
        assertThat(extractor.receivedImages).hasSize(1);
        assertThat(e.getStatus()).isEqualTo(ProcessingStatus.NOT_INCLUDED);
        assertThat(e.getMerchant()).isEqualTo("Le Bistrot");
        assertThat(e.getFilter()).isEqualTo(ImageFilter.SCAN_BW);
    }

    @Test
    void une_depense_sans_proprietaire_n_est_pas_analysee() {
        var id = UUID.randomUUID();
        var orphan = new Expense(id);
        orphan.setOriginalFile(storage.saveOriginal(id, PHOTO, "jpg"));
        repository.save(orphan);

        processor.process(id);

        assertThat(extractor.receivedImages).isEmpty();
        assertThat(repository.findById(id).orElseThrow().getStatus()).isEqualTo(ProcessingStatus.NOT_INCLUDED);
    }

    @Test
    void au_demarrage_les_depenses_sans_taille_la_recoivent_depuis_leurs_fichiers() {
        var processed = register();
        processor.process(processed);
        var pending = register();
        forgetSize(processed);
        forgetSize(pending);

        service.backfillSizes();

        assertThat(repository.findById(processed).orElseThrow().getSizeBytes()).isEqualTo(PHOTO.length + PROCESSED.length);
        assertThat(repository.findById(pending).orElseThrow().getSizeBytes()).isEqualTo(PHOTO.length);
    }

    @Test
    void une_depense_inconnue_leve_une_erreur_explicite() {
        assertThatThrownBy(() -> service.get(OWNER, UUID.randomUUID())).isInstanceOf(ExpenseNotFoundException.class);
    }

    private void forgetSize(UUID id) {
        Expense e = repository.findById(id).orElseThrow();
        e.setSizeBytes(null);
        repository.save(e);
    }

    private UUID register() {
        var id = UUID.randomUUID();
        service.register(OWNER, id, PHOTO, "image/jpeg", ImageFilter.ENHANCE, null);
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
        byte[] output = PROCESSED;

        @Override
        public ProcessedImage process(byte[] original, ImageFilter filter, Quad quad) {
            inputs.add(original);
            filters.add(filter);
            corners.add(quad);
            if (failure != null) throw failure;
            return new ProcessedImage(output, true);
        }
    }
}
