package fr.notedefrais.web;

import fr.notedefrais.imaging.Quad;
import java.io.IOException;
import java.util.Locale;
import java.util.Set;
import org.springframework.web.multipart.MultipartFile;

/** Validation des images envoyées par l'appareil (frontière HTTP). */
final class ImageUploads {

    private static final Set<String> ACCEPTED_TYPES =
            Set.of("image/jpeg", "image/jpg", "image/png", "image/webp", "image/heic");

    private ImageUploads() {}

    /** @return le type MIME (en minuscules) d'une image acceptée */
    static String requireImage(MultipartFile file) {
        if (file.isEmpty()) throw new BadRequestException("Fichier vide");
        String type = file.getContentType() == null ? "" : file.getContentType().toLowerCase(Locale.ROOT);
        if (!ACCEPTED_TYPES.contains(type)) throw new UnsupportedImageTypeException(type);
        return type;
    }

    /** Rendu calculé sur l'appareil : toujours un JPEG. */
    static byte[] requireJpeg(MultipartFile file) throws IOException {
        String type = requireImage(file);
        if (!type.equals("image/jpeg") && !type.equals("image/jpg")) throw new UnsupportedImageTypeException(type);
        return file.getBytes();
    }

    static Quad parseCorners(String corners) {
        return corners == null || corners.isBlank() ? null : Quad.parse(corners);
    }
}
