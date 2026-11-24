package fr.notedefrais.document.web;

import fr.notedefrais.account.web.SessionAuthenticationFilter;
import fr.notedefrais.web.ImageUploads;

import fr.notedefrais.document.DocumentService;
import fr.notedefrais.document.NewPage;
import fr.notedefrais.expense.ImageFilter;
import fr.notedefrais.receipt.imaging.Quad;
import jakarta.validation.Valid;
import java.io.IOException;
import java.time.Instant;
import java.util.List;
import java.util.UUID;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

/** Documents multi-pages : l'appareil envoie l'original et le rendu de chaque page (pas d'analyse IA). */
@RestController
@RequestMapping("/api/documents")
public class DocumentController {

    private final DocumentService service;

    public DocumentController(DocumentService service) {
        this.service = service;
    }

    /** Crée ou met à jour (titre, ordre des pages ; les pages absentes de l'ordre sont retirées). */
    @PutMapping("/{id}")
    public DocumentDto save(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                            @PathVariable UUID id, @Valid @RequestBody DocumentDto.Update update) {
        return DocumentDto.of(service.save(ownerId, id, update.title().strip(), update.pageIds()));
    }

    @GetMapping("/{id}")
    public DocumentDto get(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                           @PathVariable UUID id) {
        return DocumentDto.of(service.get(ownerId, id));
    }

    /** Synchronisation : tout ce qui a changé depuis {@code since}, suppressions comprises. */
    @GetMapping("/changes")
    public List<DocumentDto> changes(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                     @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant since) {
        return service.changesSince(ownerId, since).stream().map(DocumentDto::of).toList();
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                       @PathVariable UUID id) {
        service.delete(ownerId, id);
        return ResponseEntity.noContent().build();
    }

    @PostMapping(value = "/{id}/pages", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public DocumentDto.Page addPage(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                    @PathVariable UUID id,
                                    @RequestParam UUID pageId,
                                    @RequestParam MultipartFile original,
                                    @RequestParam MultipartFile processed,
                                    @RequestParam ImageFilter filter,
                                    @RequestParam(required = false) String corners) throws IOException {
        String originalType = ImageUploads.requireImage(original);
        byte[] render = ImageUploads.requireJpeg(processed);
        var page = new NewPage(pageId, original.getBytes(), originalType, render, filter, ImageUploads.parseCorners(corners));
        return DocumentDto.Page.of(service.addPage(ownerId, id, page));
    }

    /** Nouveau rendu d'une page réajustée sur l'appareil ; l'original ne change pas. */
    @PostMapping(value = "/{id}/pages/{pageId}/processed", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public DocumentDto.Page replaceRender(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                          @PathVariable UUID id, @PathVariable UUID pageId,
                                          @RequestParam MultipartFile processed,
                                          @RequestParam ImageFilter filter,
                                          @RequestParam(required = false) String corners) throws IOException {
        byte[] render = ImageUploads.requireJpeg(processed);
        return DocumentDto.Page.of(service.replaceRender(ownerId, id, pageId, render, filter,
                ImageUploads.parseCorners(corners)));
    }

    @GetMapping("/{id}/pages/{pageId}/original")
    public ResponseEntity<byte[]> original(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                           @PathVariable UUID id, @PathVariable UUID pageId) {
        String type = service.page(ownerId, id, pageId).getOriginalContentType();
        return ResponseEntity.ok()
                .contentType(type == null ? MediaType.APPLICATION_OCTET_STREAM : MediaType.parseMediaType(type))
                .body(service.original(ownerId, id, pageId));
    }

    @GetMapping(value = "/{id}/pages/{pageId}/processed", produces = MediaType.IMAGE_JPEG_VALUE)
    public byte[] processed(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                            @PathVariable UUID id, @PathVariable UUID pageId) {
        return service.processed(ownerId, id, pageId);
    }
}
