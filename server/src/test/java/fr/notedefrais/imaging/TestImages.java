package fr.notedefrais.imaging;

import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.geom.AffineTransform;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
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
