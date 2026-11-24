package fr.notedefrais.receipt.imaging;

/** Rotation demandée qui n'est pas un quart de tour (0, 90, 180 ou 270 degrés). */
public class InvalidRotationException extends RuntimeException {
    public InvalidRotationException(int degrees) {
        super("Rotation invalide : " + degrees + "° (attendu 0, 90, 180 ou 270)");
    }
}
