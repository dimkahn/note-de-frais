package fr.notedefrais.web;

public class UnsupportedImageTypeException extends RuntimeException {
    public UnsupportedImageTypeException(String type) {
        super("Type de fichier non supporté : " + (type.isBlank() ? "inconnu" : type)
                + " (attendu : JPEG, PNG, WebP ou HEIC)");
    }
}
