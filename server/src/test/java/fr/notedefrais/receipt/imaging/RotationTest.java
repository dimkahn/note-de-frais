package fr.notedefrais.receipt.imaging;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class RotationTest {

    @Test
    void se_lit_en_degres_horaires() {
        assertThat(Rotation.ofDegrees(0)).isEqualTo(Rotation.NONE);
        assertThat(Rotation.ofDegrees(90)).isEqualTo(Rotation.CLOCKWISE_90);
        assertThat(Rotation.ofDegrees(180)).isEqualTo(Rotation.CLOCKWISE_180);
        assertThat(Rotation.ofDegrees(270)).isEqualTo(Rotation.CLOCKWISE_270);
    }

    @Test
    void s_ecrit_en_degres_horaires() {
        assertThat(Rotation.CLOCKWISE_270.degrees()).isEqualTo(270);
    }

    @Test
    void refuse_un_angle_qui_n_est_pas_un_quart_de_tour() {
        assertThatThrownBy(() -> Rotation.ofDegrees(45)).isInstanceOf(InvalidRotationException.class);
        assertThatThrownBy(() -> Rotation.ofDegrees(360)).isInstanceOf(InvalidRotationException.class);
    }
}
