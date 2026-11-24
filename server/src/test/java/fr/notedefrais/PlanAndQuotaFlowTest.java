package fr.notedefrais;

import static org.hamcrest.Matchers.greaterThanOrEqualTo;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import fr.notedefrais.receipt.imaging.TestImages;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

/** Coutures réelles : offres lues dans la configuration, quota à l'envoi, administration du plan. */
@SpringBootTest(properties = {"app.api-token=secret-admin", "app.plans.free.quota=1KB"})
@AutoConfigureMockMvc
class PlanAndQuotaFlowTest {

    static final long ONE_GB = 1024L * 1024 * 1024;

    @Autowired
    MockMvc mvc;

    @Test
    void un_envoi_au_dela_du_quota_gratuit_est_refuse_puis_accepte_apres_passage_en_premium() throws Exception {
        String email = UUID.randomUUID() + "@example.com";
        var session = TestSessions.bearer(TestSessions.signUpToken(mvc, email));
        byte[] photo = TestImages.photoOfReceipt(600, 800, 250, 450, 5);
        var refused = UUID.randomUUID();

        upload(session, refused, photo)
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"))
                .andExpect(jsonPath("$.usedBytes").value(0))
                .andExpect(jsonPath("$.quotaBytes").value(1024));
        mvc.perform(get("/api/expenses/{id}", refused).with(session)).andExpect(status().isNotFound());

        mvc.perform(put("/api/admin/accounts/{email}/plan", email).header("X-Api-Token", "secret-admin")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"plan\":\"PREMIUM\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan").value("PREMIUM"));

        upload(session, refused, photo).andExpect(status().isAccepted());
        mvc.perform(get("/api/account").with(session))
                .andExpect(jsonPath("$.plan").value("PREMIUM"))
                .andExpect(jsonPath("$.quotaBytes").value(ONE_GB))
                .andExpect(jsonPath("$.aiAnalysis").value(true))
                .andExpect(jsonPath("$.usedBytes").value(greaterThanOrEqualTo(photo.length)));
    }

    @Test
    void l_administration_d_un_compte_inconnu_repond_404() throws Exception {
        mvc.perform(put("/api/admin/accounts/{email}/plan", "inconnu@example.com").header("X-Api-Token", "secret-admin")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"plan\":\"PREMIUM\"}"))
                .andExpect(status().isNotFound());
    }

    private ResultActions upload(RequestPostProcessor session, UUID id, byte[] photo) throws Exception {
        return mvc.perform(multipart("/api/expenses")
                .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", photo))
                .param("id", id.toString())
                .with(session));
    }
}
