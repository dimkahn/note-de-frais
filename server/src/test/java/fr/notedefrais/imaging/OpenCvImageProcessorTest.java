package fr.notedefrais.imaging;

import static org.assertj.core.api.Assertions.assertThat;

import fr.notedefrais.expense.ImageFilter;
import java.awt.Color;
import java.awt.image.BufferedImage;
import java.io.IOException;
import static fr.notedefrais.imaging.TestImages.*;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.EnumSource;

class OpenCvImageProcessorTest {

    // Images synthétiques : voir TestImages

    private final OpenCvImageProcessor processor = new OpenCvImageProcessor();

    @Test
    void recadre_un_ticket_photographie_de_travers_sur_fond_sombre() throws IOException {
        byte[] photo = photoOfReceipt(1200, 1600, 500, 900, 12);

        ProcessedImage result = processor.process(photo, ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getHeight()).isGreaterThan(out.getWidth());
        assertThat(out.getWidth()).isBetween(450, 560);
        assertThat(out.getHeight()).isBetween(850, 960);
    }

    @Test
    void ignore_un_grand_objet_clair_arrondi_a_cote_du_ticket() throws IOException {
        BufferedImage img = filled(1400, 1400, new Color(45, 35, 30));
        java.awt.Graphics2D g = img.createGraphics();
        g.setColor(new Color(235, 232, 225));
        g.fillPolygon(new int[] {200, 560, 540, 180}, new int[] {300, 320, 1100, 1080}, 4);
        g.setColor(new Color(225, 210, 200));
        g.rotate(Math.toRadians(15), 1050, 700);
        g.fillOval(1050 - 330, 700 - 520, 660, 1040);
        g.dispose();

        ProcessedImage result = processor.process(encode(img), ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getWidth()).isBetween(330, 400);
        assertThat(out.getHeight()).isBetween(740, 820);
    }

    @Test
    void photo_reelle_ticket_creme_pose_sur_une_feuille_blanche() throws IOException {
        // Aperçu caméra capturé sur un téléphone : peu de contraste, la feuille dépasse du cadre.
        byte[] photo;
        try (var in = getClass().getResourceAsStream("/fixtures/ticket_sur_feuille_blanche.jpg")) {
            photo = in.readAllBytes();
        }

        ProcessedImage result = processor.process(photo, ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        // Ticket ≈ 54 % x 84 % d'une image de 1220 x 1626.
        assertThat(out.getWidth()).isBetween(560, 720);
        assertThat(out.getHeight()).isBetween(1260, 1440);
    }

    @Test
    void trouve_un_ticket_dont_un_coin_chevauche_un_objet_sombre() throws IOException {
        BufferedImage img = filled(1000, 1400, new Color(120, 75, 40));
        java.awt.Graphics2D g = img.createGraphics();
        g.setColor(new Color(25, 25, 25));
        g.fillRect(0, 30, 950, 300);
        g.setColor(new Color(238, 236, 232));
        g.fillPolygon(new int[] {290, 750, 740, 250}, new int[] {220, 250, 1250, 1230}, 4);
        g.setColor(new Color(90, 90, 90));
        for (int y = 420; y < 1100; y += 50) {
            g.fillRect(330, y, 300, 12);
        }
        g.dispose();

        ProcessedImage result = processor.process(encode(img), ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getWidth()).isBetween(440, 540);
        assertThat(out.getHeight()).isBetween(950, 1060);
    }

    @Test
    void recadre_un_ticket_blanc_pose_sur_du_bois_clair() throws IOException {
        byte[] photo = photoOnLightBackground(1000, 1400, 520, 900, 4,
                new Color(215, 190, 150), new Color(245, 242, 238));

        ProcessedImage result = processor.process(photo, ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getWidth()).isBetween(480, 580);
        assertThat(out.getHeight()).isBetween(850, 960);
    }

    @Test
    void recadre_un_ticket_blanc_pose_sur_une_table_blanche() throws IOException {
        byte[] photo = photoOnLightBackground(1000, 1400, 520, 900, 4,
                new Color(216, 214, 212), new Color(247, 246, 245));

        ProcessedImage result = processor.process(photo, ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getWidth()).isBetween(480, 580);
        assertThat(out.getHeight()).isBetween(850, 960);
    }

    @Test
    void n_invente_pas_de_contour_sur_un_fond_clair_sans_document() throws IOException {
        Color table = new Color(216, 214, 212);
        byte[] photo = photoOnLightBackground(1000, 1400, 520, 900, 4, table, table);

        ProcessedImage result = processor.process(photo, ImageFilter.NONE, null);

        assertThat(result.cropped()).isFalse();
    }

    @Test
    void ne_recadre_pas_quand_aucun_document_n_est_detecte() throws IOException {
        byte[] uniform = encode(filled(800, 600, new Color(200, 200, 200)));

        ProcessedImage result = processor.process(uniform, ImageFilter.NONE, null);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isFalse();
        assertThat(out.getWidth()).isEqualTo(800);
        assertThat(out.getHeight()).isEqualTo(600);
    }

    @ParameterizedTest
    @EnumSource(ImageFilter.class)
    void chaque_filtre_produit_un_jpeg_valide(ImageFilter filter) throws IOException {
        byte[] photo = photoOfReceipt(900, 1200, 400, 700, -8);

        ProcessedImage result = processor.process(photo, filter, null);

        assertThat(decode(result.jpeg())).isNotNull();
    }

    @Test
    void le_filtre_netteté_augmente_le_contraste_local() throws IOException {
        byte[] photo = photoOfReceipt(900, 1200, 400, 700, 0);

        double plain = sharpness(processor.process(photo, ImageFilter.NONE, null).jpeg());
        double enhanced = sharpness(processor.process(photo, ImageFilter.ENHANCE, null).jpeg());

        assertThat(enhanced).isGreaterThan(plain);
    }

    @Test
    void le_mode_scan_produit_une_image_quasi_binaire() throws IOException {
        byte[] photo = photoOfReceipt(900, 1200, 400, 700, 5);

        BufferedImage out = decode(processor.process(photo, ImageFilter.SCAN_BW, null).jpeg());

        long extremes = 0, total = 0;
        for (int y = 0; y < out.getHeight(); y += 4) {
            for (int x = 0; x < out.getWidth(); x += 4) {
                int v = out.getRaster().getSample(x, y, 0);
                if (v < 40 || v > 215) extremes++;
                total++;
            }
        }
        assertThat((double) extremes / total).isGreaterThan(0.9);
    }

    @Test
    void utilise_les_coins_choisis_par_l_utilisateur_sans_detection() throws IOException {
        byte[] uniform = encode(filled(1000, 800, new Color(200, 200, 200)));
        Quad quarter = Quad.parse("0.25,0.25,0.75,0.25,0.75,0.75,0.25,0.75");

        ProcessedImage result = processor.process(uniform, ImageFilter.NONE, quarter);

        BufferedImage out = decode(result.jpeg());
        assertThat(result.cropped()).isTrue();
        assertThat(out.getWidth()).isBetween(495, 505);
        assertThat(out.getHeight()).isBetween(395, 405);
    }
}
