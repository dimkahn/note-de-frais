package fr.notedefrais.imaging;

import fr.notedefrais.expense.ImageFilter;

/** Recadrage automatique et amélioration d'une photo de justificatif. N'altère jamais l'entrée. */
public interface ImageProcessor {

    ProcessedImage process(byte[] original, ImageFilter filter);
}
