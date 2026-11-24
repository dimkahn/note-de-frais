package fr.notedefrais.document;

import fr.notedefrais.expense.ImageFilter;
import fr.notedefrais.receipt.imaging.Quad;
import java.util.UUID;

/** Page envoyée par l'appareil : son original et le rendu qu'il en a calculé. */
public record NewPage(UUID id, byte[] original, String originalContentType, byte[] processed,
                      ImageFilter filter, Quad corners) {}
