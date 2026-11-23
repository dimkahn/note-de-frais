package fr.notedefrais.storage;

import java.util.Locale;

/** Extension de fichier d'une image d'après son type MIME. */
public final class ImageTypes {

    private ImageTypes() {}

    public static String extensionOf(String contentType) {
        if (contentType == null) return "bin";
        return switch (contentType.toLowerCase(Locale.ROOT)) {
            case "image/jpeg", "image/jpg" -> "jpg";
            case "image/png" -> "png";
            case "image/webp" -> "webp";
            case "image/heic" -> "heic";
            default -> "bin";
        };
    }
}
