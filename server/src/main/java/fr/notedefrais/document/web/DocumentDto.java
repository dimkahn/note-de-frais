package fr.notedefrais.document.web;

import fr.notedefrais.document.DocumentContent;
import fr.notedefrais.document.DocumentPage;
import fr.notedefrais.receipt.imaging.ImageFilter;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

/** Représentation JSON d'un document : ses pages visibles, dans l'ordre. */
public record DocumentDto(UUID id, String title, List<Page> pages, boolean deleted, Instant createdAt,
                          Instant updatedAt) {

    /** Titre et ordre complet des pages voulus par l'appareil. */
    public record Update(@NotBlank @Size(max = 200) String title, @NotNull @Size(max = 500) List<@NotNull UUID> pageIds) {}

    public record Page(UUID id, ImageFilter filter, String corners, int rotation, int renderVersion) {
        static Page of(DocumentPage p) {
            return new Page(p.getId(), p.getFilter(), p.getCorners(), p.getRotation().degrees(), p.getRenderVersion());
        }
    }

    static DocumentDto of(DocumentContent c) {
        var d = c.document();
        return new DocumentDto(d.getId(), d.getTitle(), c.pages().stream().map(Page::of).toList(), d.isDeleted(),
                d.getCreatedAt(), d.getUpdatedAt());
    }
}
