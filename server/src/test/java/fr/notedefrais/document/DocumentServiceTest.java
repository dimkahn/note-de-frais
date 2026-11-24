package fr.notedefrais.document;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import fr.notedefrais.account.PlanLimits;
import fr.notedefrais.account.Quota;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.expense.ExpenseRepository;
import fr.notedefrais.expense.ImageFilter;
import fr.notedefrais.receipt.imaging.Quad;
import fr.notedefrais.storage.LocalFileStorage;
import java.nio.file.Path;
import java.time.Instant;
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
class DocumentServiceTest {

    static final UUID OWNER = UUID.randomUUID();
    static final UUID STRANGER = UUID.randomUUID();
    static final byte[] PHOTO = {10, 20, 30};
    static final byte[] RENDER = {99, 98};
    static final Quad CORNERS = Quad.parse("0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9");

    @Autowired
    DocumentRepository documents;
    @Autowired
    DocumentPageRepository pages;
    @Autowired
    ExpenseRepository expenses;
    @TempDir
    Path storageDir;

    LocalFileStorage storage;
    PlanLimits limits;
    Quota quota;
    DocumentService service;

    @BeforeEach
    void setUp() {
        pages.deleteAll();
        documents.deleteAll();
        expenses.deleteAll();
        storage = new LocalFileStorage(storageDir);
        limits = new PlanLimits(1_000_000, false);
        quota = new Quota(List.of(expenses, pages), owner -> limits);
        service = new DocumentService(documents, pages, storage, quota);
    }

    @Test
    void cree_un_document_avec_son_titre_et_sans_page() {
        var id = UUID.randomUUID();

        DocumentContent created = service.save(OWNER, id, "Contrat de bail", List.of());

        assertThat(created.document().getTitle()).isEqualTo("Contrat de bail");
        assertThat(created.pages()).isEmpty();
        assertThat(service.get(OWNER, id).document().getTitle()).isEqualTo("Contrat de bail");
    }

    @Test
    void renomme_un_document_existant() {
        var id = UUID.randomUUID();
        service.save(OWNER, id, "Brouillon", List.of());

        service.save(OWNER, id, "Attestation", List.of());

        assertThat(service.get(OWNER, id).document().getTitle()).isEqualTo("Attestation");
        assertThat(documents.count()).isEqualTo(1);
    }

    @Test
    void le_document_d_un_autre_compte_est_introuvable_et_inchange() {
        var id = UUID.randomUUID();
        service.save(OWNER, id, "À moi", List.of());

        assertThatThrownBy(() -> service.get(STRANGER, id)).isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.save(STRANGER, id, "Pirate", List.of()))
                .isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.delete(STRANGER, id)).isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.addPage(STRANGER, id, page(UUID.randomUUID())))
                .isInstanceOf(DocumentNotFoundException.class);
        assertThat(service.get(OWNER, id).document().getTitle()).isEqualTo("À moi");
    }

    @Test
    void ajoute_une_page_avec_son_original_et_son_rendu() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));

        DocumentPage added = service.addPage(OWNER, id, page(pageId));

        assertThat(added.getRenderVersion()).isEqualTo(1);
        assertThat(added.getFilter()).isEqualTo(ImageFilter.SCAN_BW);
        assertThat(added.getCorners()).isEqualTo(CORNERS.format());
        assertThat(service.original(OWNER, id, pageId)).containsExactly(PHOTO);
        assertThat(service.processed(OWNER, id, pageId)).containsExactly(RENDER);
        assertThat(service.get(OWNER, id).pages()).extracting(DocumentPage::getId).containsExactly(pageId);
    }

    @Test
    void renvoyer_une_page_deja_recue_ne_touche_ni_son_original_ni_son_rendu() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        service.addPage(OWNER, id, page(pageId));

        DocumentPage again = service.addPage(OWNER, id,
                new NewPage(pageId, new byte[]{1}, "image/jpeg", new byte[]{2}, ImageFilter.NONE, null));

        assertThat(again.getRenderVersion()).isEqualTo(1);
        assertThat(service.original(OWNER, id, pageId)).containsExactly(PHOTO);
        assertThat(service.processed(OWNER, id, pageId)).containsExactly(RENDER);
    }

    @Test
    void une_page_d_un_autre_document_est_introuvable() {
        var mine = UUID.randomUUID();
        var other = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, mine, "A", List.of(pageId));
        service.save(OWNER, other, "B", List.of(pageId));
        service.addPage(OWNER, mine, page(pageId));

        assertThatThrownBy(() -> service.addPage(OWNER, other, page(pageId)))
                .isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.original(OWNER, other, pageId))
                .isInstanceOf(DocumentNotFoundException.class);
    }

    @Test
    void les_pages_suivent_l_ordre_demande_meme_cite_avant_leur_envoi() {
        var id = UUID.randomUUID();
        var first = UUID.randomUUID();
        var second = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(second, first));

        service.addPage(OWNER, id, page(first));
        service.addPage(OWNER, id, page(second));

        assertThat(service.get(OWNER, id).pages()).extracting(DocumentPage::getId).containsExactly(second, first);
        service.save(OWNER, id, "Contrat", List.of(first, second));
        assertThat(service.get(OWNER, id).pages()).extracting(DocumentPage::getId).containsExactly(first, second);
    }

    @Test
    void une_page_absente_de_l_ordre_est_retiree_mais_son_original_reste_stocke() {
        var id = UUID.randomUUID();
        var kept = UUID.randomUUID();
        var removed = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(kept, removed));
        service.addPage(OWNER, id, page(kept));
        DocumentPage removedPage = service.addPage(OWNER, id, page(removed));

        service.save(OWNER, id, "Contrat", List.of(kept));

        assertThat(service.get(OWNER, id).pages()).extracting(DocumentPage::getId).containsExactly(kept);
        assertThat(pages.findById(removed).orElseThrow().isRemoved()).isTrue();
        assertThat(storage.read(removed, removedPage.getOriginalFile())).containsExactly(PHOTO);
    }

    @Test
    void un_nouveau_rendu_remplace_le_precedent_sans_toucher_l_original() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        service.addPage(OWNER, id, page(pageId));
        Quad tighter = Quad.parse("0.2,0.2,0.8,0.2,0.8,0.8,0.2,0.8");

        DocumentPage adjusted = service.replaceRender(OWNER, id, pageId, new byte[]{5, 5, 5, 5}, ImageFilter.SHARPEN, tighter);

        assertThat(adjusted.getRenderVersion()).isEqualTo(2);
        assertThat(adjusted.getFilter()).isEqualTo(ImageFilter.SHARPEN);
        assertThat(adjusted.getCorners()).isEqualTo(tighter.format());
        assertThat(service.processed(OWNER, id, pageId)).containsExactly(5, 5, 5, 5);
        assertThat(service.original(OWNER, id, pageId)).containsExactly(PHOTO);
        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length + 4);
    }

    @Test
    void un_changement_de_page_fait_remonter_le_document_dans_les_changements() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        Instant before = service.get(OWNER, id).document().getUpdatedAt();

        service.addPage(OWNER, id, page(pageId));

        assertThat(service.changesSince(OWNER, before)).extracting(c -> c.document().getId()).containsExactly(id);
    }

    @Test
    void les_changements_ne_concernent_que_le_compte_et_comprennent_les_suppressions() {
        var deleted = UUID.randomUUID();
        service.save(OWNER, deleted, "Ancien", List.of());
        service.save(STRANGER, UUID.randomUUID(), "Autre compte", List.of());

        service.delete(OWNER, deleted);

        List<DocumentContent> changes = service.changesSince(OWNER, Instant.EPOCH);
        assertThat(changes).extracting(c -> c.document().getId()).containsExactly(deleted);
        assertThat(changes.getFirst().document().isDeleted()).isTrue();
        assertThatThrownBy(() -> service.get(OWNER, deleted)).isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.save(OWNER, deleted, "Ressuscité", List.of()))
                .isInstanceOf(DocumentNotFoundException.class);
    }

    @Test
    void l_usage_compte_les_pages_mais_ni_les_retirees_ni_celles_des_documents_supprimes() {
        var kept = UUID.randomUUID();
        var deleted = UUID.randomUUID();
        var keptPage = UUID.randomUUID();
        var removedPage = UUID.randomUUID();
        var deletedPage = UUID.randomUUID();
        service.save(OWNER, kept, "Gardé", List.of(keptPage, removedPage));
        service.save(OWNER, deleted, "Supprimé", List.of(deletedPage));
        service.addPage(OWNER, kept, page(keptPage));
        service.addPage(OWNER, kept, page(removedPage));
        service.addPage(OWNER, deleted, page(deletedPage));

        service.save(OWNER, kept, "Gardé", List.of(keptPage));
        service.delete(OWNER, deleted);

        assertThat(quota.usedBytes(OWNER)).isEqualTo(PHOTO.length + RENDER.length);
    }

    @Test
    void une_page_qui_depasserait_le_quota_est_refusee_sans_rien_stocker() {
        limits = new PlanLimits(PHOTO.length + RENDER.length + 1, false);
        var id = UUID.randomUUID();
        var accepted = UUID.randomUUID();
        var refused = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(accepted, refused));
        service.addPage(OWNER, id, page(accepted));

        var error = catchThrowableOfType(QuotaExceededException.class, () -> service.addPage(OWNER, id, page(refused)));

        assertThat(error.usedBytes()).isEqualTo(PHOTO.length + RENDER.length);
        assertThat(pages.findById(refused)).isEmpty();
        assertThat(storageDir.resolve(refused.toString())).doesNotExist();
    }

    @Test
    void renvoyer_une_page_deja_recue_n_est_jamais_refuse_pour_quota() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        service.addPage(OWNER, id, page(pageId));
        limits = new PlanLimits(1, false);

        DocumentPage again = service.addPage(OWNER, id, page(pageId));

        assertThat(again.getId()).isEqualTo(pageId);
    }

    @Test
    void reintegrer_une_page_retiree_au_dela_du_quota_est_refuse() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        service.addPage(OWNER, id, page(pageId));
        service.save(OWNER, id, "Contrat", List.of());
        limits = new PlanLimits(PHOTO.length + RENDER.length - 1, false);

        assertThatThrownBy(() -> service.save(OWNER, id, "Contrat", List.of(pageId)))
                .isInstanceOf(QuotaExceededException.class);

        assertThat(service.get(OWNER, id).pages()).isEmpty();
        assertThat(quota.usedBytes(OWNER)).isZero();
    }

    @Test
    void un_identifiant_de_page_repete_dans_l_ordre_n_est_compte_qu_une_fois() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId, pageId));

        service.addPage(OWNER, id, page(pageId));

        assertThat(service.get(OWNER, id).pages()).extracting(DocumentPage::getId).containsExactly(pageId);
    }

    @Test
    void un_nouveau_rendu_n_est_jamais_refuse_pour_quota() {
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(pageId));
        service.addPage(OWNER, id, page(pageId));
        limits = new PlanLimits(1, false);

        DocumentPage adjusted = service.replaceRender(OWNER, id, pageId, new byte[10], ImageFilter.NONE, null);

        assertThat(adjusted.getRenderVersion()).isEqualTo(2);
    }

    @Test
    void le_rendu_d_une_page_retiree_ou_d_un_autre_compte_ne_peut_pas_etre_remplace() {
        var id = UUID.randomUUID();
        var removed = UUID.randomUUID();
        service.save(OWNER, id, "Contrat", List.of(removed));
        service.addPage(OWNER, id, page(removed));
        service.save(OWNER, id, "Contrat", List.of());

        assertThatThrownBy(() -> service.replaceRender(OWNER, id, removed, RENDER, ImageFilter.NONE, null))
                .isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.replaceRender(STRANGER, id, removed, RENDER, ImageFilter.NONE, null))
                .isInstanceOf(DocumentNotFoundException.class);
        assertThatThrownBy(() -> service.replaceRender(OWNER, id, UUID.randomUUID(), RENDER, ImageFilter.NONE, null))
                .isInstanceOf(DocumentNotFoundException.class);
    }

    private static NewPage page(UUID id) {
        return new NewPage(id, PHOTO, "image/jpeg", RENDER, ImageFilter.SCAN_BW, CORNERS);
    }
}
