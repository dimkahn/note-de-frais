package fr.notedefrais.receipt.imaging;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.Random;
import javax.imageio.ImageIO;

/** Images synthétiques pour les tests (aucune photo réelle dans le dépôt). */
public final class TestImages {

    private TestImages() {}


    /** Ticket blanc avec lignes de « texte » gris, tourné de {@code angle} degrés sur une table sombre. */
    public static byte[] photoOfReceipt(int w, int h, int rw, int rh, double angle) throws IOException {
        BufferedImage img = filled(w, h, new Color(45, 35, 30));
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setTransform(AffineTransform.getRotateInstance(Math.toRadians(angle), w / 2.0, h / 2.0));
        int x0 = (w - rw) / 2, y0 = (h - rh) / 2;
        g.setColor(new Color(235, 232, 225));
        g.fillRect(x0, y0, rw, rh);
        g.setColor(new Color(110, 110, 110));
        for (int y = y0 + 40; y < y0 + rh - 40; y += 28) {
            g.fillRect(x0 + 30, y, rw - 60 - (y % 3) * 40, 9);
        }
        g.dispose();
        return encode(img);
    }

    /**
     * Ticket peu contrasté sur fond clair, comme une vraie photo : éclairage en dégradé (ombre douce
     * d'un côté) et bruit de capteur. {@code paper == background} : aucun document visible.
     */
    public static byte[] photoOnLightBackground(int w, int h, int rw, int rh, double angle,
                                                Color background, Color paper) throws IOException {
        BufferedImage img = filled(w, h, background);
        Graphics2D g = img.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setTransform(AffineTransform.getRotateInstance(Math.toRadians(angle), w / 2.0, h / 2.0));
        int x0 = (w - rw) / 2, y0 = (h - rh) / 2;
        g.setColor(paper);
        g.fillRect(x0, y0, rw, rh);
        g.setColor(new Color(90, 90, 90));
        for (int y = y0 + 60; y < y0 + 400; y += 40) {
            g.fillRect(x0 + 60, y, 220, 10);
        }
        g.dispose();
        Random noise = new Random(42);
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int shade = (int) Math.round(x / (double) w * 40);
                int rgb = img.getRGB(x, y);
                int r = clamp(((rgb >> 16) & 0xFF) - shade + (int) (noise.nextGaussian() * 6));
                int gr = clamp(((rgb >> 8) & 0xFF) - shade + (int) (noise.nextGaussian() * 6));
                int b = clamp((rgb & 0xFF) - shade + (int) (noise.nextGaussian() * 6));
                img.setRGB(x, y, (r << 16) | (gr << 8) | b);
            }
        }
        return encode(img);
    }

    private static int clamp(int v) {
        return Math.max(0, Math.min(255, v));
    }

    public static BufferedImage filled(int w, int h, Color c) {
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setColor(c);
        g.fillRect(0, 0, w, h);
        g.dispose();
        return img;
    }

    public static byte[] encode(BufferedImage img) throws IOException {
        var out = new ByteArrayOutputStream();
        ImageIO.write(img, "jpg", out);
        return out.toByteArray();
    }

    public static BufferedImage decode(byte[] jpeg) throws IOException {
        return ImageIO.read(new ByteArrayInputStream(jpeg));
    }

    /** Somme des gradients absolus horizontaux (mesure simple de netteté / contraste local). */
    public static double sharpness(byte[] jpeg) throws IOException {
        BufferedImage img = decode(jpeg);
        double sum = 0;
        for (int y = 0; y < img.getHeight(); y += 2) {
            for (int x = 1; x < img.getWidth(); x++) {
                int a = img.getRGB(x, y) & 0xFF, b = img.getRGB(x - 1, y) & 0xFF;
                sum += Math.abs(a - b);
            }
        }
        return sum / (img.getWidth() * (double) img.getHeight());
    }
}
