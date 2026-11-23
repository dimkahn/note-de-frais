package fr.notedefrais.imaging;

import java.util.List;
import java.util.Locale;
import java.util.stream.Collectors;

/**
 * Contour du document choisi par l'utilisateur : 4 coins normalisés (0..1) dans le repère de
 * l'image orientée (EXIF appliqué), dans l'ordre haut-gauche, haut-droit, bas-droit, bas-gauche.
 * Format texte partagé avec l'app : {@code "x1,y1,x2,y2,x3,y3,x4,y4"}.
 */
public record Quad(Corner topLeft, Corner topRight, Corner bottomRight, Corner bottomLeft) {

    public record Corner(double x, double y) {}

    public Quad {
        for (Corner c : List.of(topLeft, topRight, bottomRight, bottomLeft)) {
            if (c.x() < 0 || c.x() > 1 || c.y() < 0 || c.y() > 1 || Double.isNaN(c.x()) || Double.isNaN(c.y())) {
                throw new InvalidQuadException("Coin hors de l'image : " + c);
            }
        }
        if (!isStrictlyConvex(List.of(topLeft, topRight, bottomRight, bottomLeft))) {
            throw new InvalidQuadException("Le contour doit être un quadrilatère convexe non dégénéré");
        }
    }

    public static Quad parse(String text) {
        String[] parts = text == null ? new String[0] : text.split(",");
        if (parts.length != 8) {
            throw new InvalidQuadException("8 coordonnées attendues, reçu " + parts.length);
        }
        double[] v = new double[8];
        try {
            for (int i = 0; i < 8; i++) v[i] = Double.parseDouble(parts[i].strip());
        } catch (NumberFormatException e) {
            throw new InvalidQuadException("Coordonnée non numérique dans « " + text + " »");
        }
        return new Quad(new Corner(v[0], v[1]), new Corner(v[2], v[3]),
                new Corner(v[4], v[5]), new Corner(v[6], v[7]));
    }

    public String format() {
        return corners().stream()
                .flatMap(c -> java.util.stream.Stream.of(c.x(), c.y()))
                .map(d -> String.format(Locale.ROOT, "%.5f", d).replaceAll("0+$", "").replaceAll("\\.$", ""))
                .collect(Collectors.joining(","));
    }

    public List<Corner> corners() {
        return List.of(topLeft, topRight, bottomRight, bottomLeft);
    }

    /** Coins en pixels pour une image de {@code width} × {@code height}. */
    public double[][] toPixels(int width, int height) {
        return corners().stream().map(c -> new double[]{c.x() * width, c.y() * height}).toArray(double[][]::new);
    }

    private static boolean isStrictlyConvex(List<Corner> pts) {
        int sign = 0;
        for (int i = 0; i < 4; i++) {
            Corner a = pts.get(i), b = pts.get((i + 1) % 4), c = pts.get((i + 2) % 4);
            double cross = (b.x() - a.x()) * (c.y() - b.y()) - (b.y() - a.y()) * (c.x() - b.x());
            if (Math.abs(cross) < 1e-6) return false;
            int s = cross > 0 ? 1 : -1;
            if (sign != 0 && s != sign) return false;
            sign = s;
        }
        return true;
    }

    @Override
    public String toString() {
        return "Quad[" + format() + "]";
    }
}
