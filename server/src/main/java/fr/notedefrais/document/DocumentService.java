package fr.notedefrais.document;

import fr.notedefrais.account.Quota;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.expense.ImageFilter;
import fr.notedefrais.receipt.imaging.Quad;
import fr.notedefrais.storage.FileStorage;
import fr.notedefrais.storage.ImageTypes;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.util.stream.Collectors;
import org.springframework.transaction.annotation.Transactional;

/** Documents multi-pages d'un compte (branché dans {@code InfrastructureConfig}, avec son propre stockage). */
public class DocumentService {

    private final DocumentRepository documents;
    private final DocumentPageRepository pages;
    private final FileStorage storage;
    private final Quota quota;

    public DocumentService(DocumentRepository documents, DocumentPageRepository pages, FileStorage storage,
                           Quota quota) {
        this.documents = documents;
        this.pages = pages;
        this.storage = storage;
        this.quota = quota;
    }

    /**
     * Crée le document s'il n'existe pas, sinon le renomme ; fixe l'ordre des pages. Les pages reçues
     * absentes de {@code pageIds} sont retirées (logiquement : leurs fichiers restent stockés).
     *
     * @throws QuotaExceededException si des pages retirées réintégrées feraient dépasser l'offre
     */
    @Transactional
    public DocumentContent save(UUID ownerId, UUID id, String title, List<UUID> pageIds) {
        Document document = documents.findById(id)
                .map(existing -> visible(existing, ownerId))
                .orElseGet(() -> new Document(id, ownerId, title));
        document.rename(title);
        document.reorder(pageIds);
        List<DocumentPage> received = pages.findByDocumentId(id);
        long reinstated = received.stream()
                .filter(page -> page.isRemoved() && document.lists(page.getId()))
                .mapToLong(DocumentPage::getSizeBytes).sum();
        if (reinstated > 0) quota.ensureRoomFor(ownerId, reinstated);
        received.forEach(page -> page.setRemoved(!document.lists(page.getId())));
        pages.saveAll(received);
        return content(documents.save(document));
    }

    /**
     * Enregistre une page et son rendu. Idempotent : le renvoi d'une page déjà reçue (reprise de
     * synchronisation) la rend telle quelle, sans toucher à ses fichiers ni contrôler le quota.
     *
     * @throws QuotaExceededException si original + rendu feraient dépasser l'offre (rien n'est stocké)
     */
    @Transactional
    public DocumentPage addPage(UUID ownerId, UUID documentId, NewPage page) {
        Document document = owned(ownerId, documentId);
        var existing = pages.findById(page.id());
        if (existing.isPresent()) {
            if (!existing.get().belongsTo(ownerId, documentId)) throw new DocumentNotFoundException(documentId);
            return existing.get();
        }

        quota.ensureRoomFor(ownerId, (long) page.original().length + page.processed().length);
        String original = storage.saveOriginal(page.id(), page.original(), ImageTypes.extensionOf(page.originalContentType()));
        var added = new DocumentPage(page.id(), documentId, ownerId, original, page.originalContentType(),
                page.original().length);
        render(added, page.processed(), page.filter(), page.corners());
        added.setRemoved(!document.lists(page.id()));
        return savePageOf(document, added);
    }

    /** Remplace le rendu d'une page réajustée sur l'appareil ; l'original ne change pas. */
    @Transactional
    public DocumentPage replaceRender(UUID ownerId, UUID documentId, UUID pageId, byte[] processed,
                                      ImageFilter filter, Quad corners) {
        Document document = owned(ownerId, documentId);
        DocumentPage page = visiblePage(document, pageId);
        render(page, processed, filter, corners);
        return savePageOf(document, page);
    }

    @Transactional(readOnly = true)
    public DocumentContent get(UUID ownerId, UUID id) {
        return content(owned(ownerId, id));
    }

    /** Tous les documents du compte modifiés (y compris supprimés) depuis {@code since}, pour la synchro. */
    @Transactional(readOnly = true)
    public List<DocumentContent> changesSince(UUID ownerId, Instant since) {
        return documents.findByOwnerIdAndUpdatedAtAfterOrderByUpdatedAtAsc(ownerId, since).stream()
                .map(this::content).toList();
    }

    /** Suppression logique : se propage aux autres appareils et libère le quota ; fichiers conservés. */
    @Transactional
    public void delete(UUID ownerId, UUID id) {
        Document document = owned(ownerId, id);
        document.markDeleted();
        documents.save(document);
    }

    @Transactional(readOnly = true)
    public DocumentPage page(UUID ownerId, UUID documentId, UUID pageId) {
        return visiblePage(owned(ownerId, documentId), pageId);
    }

    public byte[] original(UUID ownerId, UUID documentId, UUID pageId) {
        return storage.read(pageId, page(ownerId, documentId, pageId).getOriginalFile());
    }

    public byte[] processed(UUID ownerId, UUID documentId, UUID pageId) {
        return storage.read(pageId, page(ownerId, documentId, pageId).getProcessedFile());
    }

    private void render(DocumentPage page, byte[] processed, ImageFilter filter, Quad corners) {
        page.render(storage.saveProcessed(page.getId(), processed), processed.length,
                filter, corners == null ? null : corners.format());
    }

    private DocumentPage savePageOf(Document document, DocumentPage page) {
        DocumentPage saved = pages.save(page);
        document.touch();
        documents.save(document);
        return saved;
    }

    private Document owned(UUID ownerId, UUID id) {
        return documents.findById(id).map(d -> visible(d, ownerId)).orElseThrow(() -> new DocumentNotFoundException(id));
    }

    private static Document visible(Document document, UUID ownerId) {
        if (document.isDeleted() || !document.isOwnedBy(ownerId)) throw new DocumentNotFoundException(document.getId());
        return document;
    }

    private DocumentPage visiblePage(Document document, UUID pageId) {
        return pages.findById(pageId)
                .filter(p -> p.belongsTo(document.getOwnerId(), document.getId()) && !p.isRemoved())
                .orElseThrow(() -> new DocumentNotFoundException(document.getId()));
    }

    /** Pages reçues et non retirées, dans l'ordre voulu par l'appareil. */
    private DocumentContent content(Document document) {
        Map<UUID, DocumentPage> received = pages.findByDocumentId(document.getId()).stream()
                .filter(p -> !p.isRemoved())
                .collect(Collectors.toMap(DocumentPage::getId, p -> p));
        List<DocumentPage> ordered = document.getPageOrder().stream()
                .map(received::get).filter(Objects::nonNull).toList();
        return new DocumentContent(document, ordered);
    }
}
