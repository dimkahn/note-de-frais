package fr.notedefrais.receipt.imaging;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;

class QuadTest {

    @Test
    void lit_huit_coordonnees_normalisees_dans_l_ordre_hg_hd_bd_bg() {
        Quad q = Quad.parse("0.1,0.2, 0.9,0.15, 0.95,0.9, 0.05,0.85");

        assertThat(q.topLeft()).isEqualTo(new Quad.Corner(0.1, 0.2));
        assertThat(q.bottomLeft()).isEqualTo(new Quad.Corner(0.05, 0.85));
    }

    @Test
    void s_ecrit_dans_le_meme_format() {
        Quad q = Quad.parse("0.1,0.2,0.9,0.15,0.95,0.9,0.05,0.85");

        assertThat(Quad.parse(q.format())).isEqualTo(q);
    }

    @Test
    void refuse_un_nombre_de_valeurs_incorrect() {
        assertThatThrownBy(() -> Quad.parse("0.1,0.2,0.3")).isInstanceOf(InvalidQuadException.class);
    }

    @Test
    void refuse_une_valeur_hors_de_l_image() {
        assertThatThrownBy(() -> Quad.parse("0,0,1.2,0,1,1,0,1")).isInstanceOf(InvalidQuadException.class);
    }

    @Test
    void refuse_un_texte_non_numerique() {
        assertThatThrownBy(() -> Quad.parse("a,0,1,0,1,1,0,1")).isInstanceOf(InvalidQuadException.class);
    }

    @Test
    void refuse_un_quadrilatere_croise() {
        // haut-droit et bas-droit inversés : les côtés se croisent
        assertThatThrownBy(() -> Quad.parse("0,0,1,1,1,0,0,1")).isInstanceOf(InvalidQuadException.class);
    }

    @Test
    void refuse_un_quadrilatere_degenere() {
        assertThatThrownBy(() -> Quad.parse("0.5,0.5,0.5,0.5,0.5,0.5,0.5,0.5")).isInstanceOf(InvalidQuadException.class);
    }
}
