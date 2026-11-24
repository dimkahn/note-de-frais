package fr.notedefrais.receipt.imaging;

/** Recadrage automatique et amélioration d'une photo de justificatif. N'altère jamais l'entrée. */
public interface ImageProcessor {

    /**
     * @param corners  contour choisi par l'utilisateur ; {@code null} = détection automatique
     * @param rotation quart de tour horaire appliqué au résultat
     */
    ProcessedImage process(byte[] original, ImageFilter filter, Quad corners, Rotation rotation);
}
