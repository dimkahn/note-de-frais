package fr.notedefrais.receipt.imaging;

import java.util.Arrays;

/** Quart de tour horaire appliqué au rendu, après redressement et filtre. L'original n'est pas touché. */
public enum Rotation {
    NONE(0), CLOCKWISE_90(90), CLOCKWISE_180(180), CLOCKWISE_270(270);

    private final int degrees;

    Rotation(int degrees) {
        this.degrees = degrees;
    }

    public static Rotation ofDegrees(int degrees) {
        return Arrays.stream(values())
                .filter(r -> r.degrees == degrees)
                .findFirst()
                .orElseThrow(() -> new InvalidRotationException(degrees));
    }

    public int degrees() {
        return degrees;
    }
}
