package fr.notedefrais;

import static org.assertj.core.api.Assertions.assertThat;
import static org.awaitility.Awaitility.await;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import fr.notedefrais.imaging.TestImages;
import java.time.Duration;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;

/** Parcours complet avec le vrai contexte : upload → recadrage OpenCV → image traitée servie, original intact. */
@SpringBootTest
@AutoConfigureMockMvc
class ExpenseFlowTest {

    @Autowired
    MockMvc mvc;

    @Test
    void un_ticket_envoye_en_gratuit_est_recadre_sans_analyse_et_compte_dans_l_usage() throws Exception {
        var session = TestSessions.signUp(mvc);
        var id = UUID.randomUUID();
        byte[] photo = TestImages.photoOfReceipt(1200, 1600, 500, 900, 10);

        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", photo))
                        .param("id", id.toString())
                        .with(session))
                .andExpect(status().isAccepted());

        // Offre gratuite : pas d'analyse IA, le traitement se termine en NOT_INCLUDED avec l'image recadrée.
        await().atMost(Duration.ofSeconds(20)).untilAsserted(() ->
                mvc.perform(get("/api/expenses/{id}", id).with(session))
                        .andExpect(jsonPath("$.status").value("NOT_INCLUDED"))
                        .andExpect(jsonPath("$.cropped").value(true))
                        .andExpect(jsonPath("$.hasProcessedImage").value(true)));

        byte[] original = mvc.perform(get("/api/expenses/{id}/original", id).with(session))
                .andReturn().getResponse().getContentAsByteArray();
        assertThat(original).isEqualTo(photo);
        byte[] processed = mvc.perform(get("/api/expenses/{id}/processed", id).with(session))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsByteArray();
        mvc.perform(get("/api/account").with(session))
                .andExpect(jsonPath("$.usedBytes").value(photo.length + processed.length))
                .andExpect(jsonPath("$.aiAnalysis").value(false));
    }
}
