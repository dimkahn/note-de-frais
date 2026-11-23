package fr.notedefrais.web;

import fr.notedefrais.expense.*;
import fr.notedefrais.expense.ExpenseSpecs.Criteria;
import fr.notedefrais.imaging.Quad;
import jakarta.validation.Valid;
import java.io.IOException;
import java.net.URI;
import java.time.Instant;
import java.time.LocalDate;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@RestController
@RequestMapping("/api/expenses")
public class ExpenseController {

    private static final Set<String> ACCEPTED_TYPES =
            Set.of("image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic");

    private final ExpenseService service;

    public ExpenseController(ExpenseService service) {
        this.service = service;
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    public ResponseEntity<ExpenseDto> upload(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                             @RequestParam("file") MultipartFile file,
                                             @RequestParam(required = false) UUID id,
                                             @RequestParam(required = false) ImageFilter filter,
                                             @RequestParam(required = false) String corners) throws IOException {
        if (file.isEmpty()) throw new BadRequestException("Fichier vide");
        String type = file.getContentType() == null ? "" : file.getContentType().toLowerCase();
        if (!ACCEPTED_TYPES.contains(type)) throw new UnsupportedImageTypeException(type);

        UUID expenseId = id == null ? UUID.randomUUID() : id;
        Expense expense = service.register(ownerId, expenseId, file.getBytes(), type, filter, parseCorners(corners));
        return ResponseEntity.accepted()
                .location(URI.create("/api/expenses/" + expenseId))
                .body(ExpenseDto.of(expense));
    }

    @GetMapping
    public List<ExpenseDto> search(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                   @RequestParam(required = false) Category category,
                                   @RequestParam(required = false) String city,
                                   @RequestParam(required = false) String country,
                                   @RequestParam(required = false) String merchant,
                                   @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                   @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                                   @RequestParam(required = false) String q) {
        return service.search(ownerId, new Criteria(category, city, country, merchant, from, to, q)).stream()
                .map(ExpenseDto::of).toList();
    }

    @GetMapping("/summary")
    public List<ExpenseSummary.Group> summary(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                              @RequestParam ExpenseSummary.GroupBy groupBy,
                                              @RequestParam(required = false) Category category,
                                              @RequestParam(required = false) String city,
                                              @RequestParam(required = false) String country,
                                              @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                                              @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to) {
        return service.summary(ownerId, new Criteria(category, city, country, null, from, to, null), groupBy);
    }

    /** Synchronisation : tout ce qui a changé depuis {@code since}, suppressions comprises. */
    @GetMapping("/changes")
    public List<ExpenseDto> changes(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                    @RequestParam @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) Instant since) {
        return service.changesSince(ownerId, since).stream().map(ExpenseDto::of).toList();
    }

    @GetMapping("/{id}")
    public ExpenseDto get(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId, @PathVariable UUID id) {
        return ExpenseDto.of(service.get(ownerId, id));
    }

    @PutMapping("/{id}")
    public ExpenseDto update(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId, @PathVariable UUID id, @Valid @RequestBody ExpenseUpdate update) {
        return ExpenseDto.of(service.update(ownerId, id, update));
    }

    @PostMapping("/{id}/reprocess")
    public ResponseEntity<ExpenseDto> reprocess(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId,
                                                @PathVariable UUID id,
                                                @RequestParam(required = false) ImageFilter filter,
                                                @RequestParam(required = false) String corners) {
        return ResponseEntity.accepted().body(ExpenseDto.of(service.reprocess(ownerId, id, filter, parseCorners(corners))));
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId, @PathVariable UUID id) {
        service.delete(ownerId, id);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{id}/original")
    public ResponseEntity<byte[]> original(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId, @PathVariable UUID id) {
        String type = service.get(ownerId, id).getOriginalContentType();
        return ResponseEntity.ok()
                .contentType(type == null ? MediaType.APPLICATION_OCTET_STREAM : MediaType.parseMediaType(type))
                .body(service.original(ownerId, id));
    }

    @GetMapping(value = "/{id}/processed", produces = MediaType.IMAGE_JPEG_VALUE)
    public byte[] processed(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID ownerId, @PathVariable UUID id) {
        return service.processed(ownerId, id);
    }

    private static Quad parseCorners(String corners) {
        return corners == null || corners.isBlank() ? null : Quad.parse(corners);
    }
}
