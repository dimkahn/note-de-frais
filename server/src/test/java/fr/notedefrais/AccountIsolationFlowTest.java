package fr.notedefrais;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import fr.notedefrais.imaging.TestImages;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

/** Coutures réelles : filtre de session, contrôleurs, service et base. */
@SpringBootTest
@AutoConfigureMockMvc
class AccountIsolationFlowTest {

    @Autowired
    MockMvc mvc;

    @Test
    void l_api_des_depenses_repond_401_sans_session() throws Exception {
        mvc.perform(get("/api/expenses")).andExpect(status().isUnauthorized());
    }

    @Test
    void un_compte_n_accede_jamais_a_la_depense_d_un_autre() throws Exception {
        var alice = TestSessions.signUp(mvc);
        var bob = TestSessions.signUp(mvc);
        var id = upload(alice);

        mvc.perform(get("/api/expenses/{id}", id).with(bob)).andExpect(status().isNotFound());
        mvc.perform(get("/api/expenses/{id}/original", id).with(bob)).andExpect(status().isNotFound());
        mvc.perform(put("/api/expenses/{id}", id).with(bob)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"merchant\":\"Pirate\"}"))
                .andExpect(status().isNotFound());
        mvc.perform(delete("/api/expenses/{id}", id).with(bob)).andExpect(status().isNotFound());
        mvc.perform(get("/api/expenses").with(bob)).andExpect(jsonPath("$.length()").value(0));
        mvc.perform(get("/api/expenses/changes").param("since", "2000-01-01T00:00:00Z").with(bob))
                .andExpect(jsonPath("$.length()").value(0));

        mvc.perform(get("/api/expenses/{id}", id).with(alice))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deleted").value(false));
    }

    @Test
    void le_compte_connecte_est_decrit_puis_la_deconnexion_revoque_la_session() throws Exception {
        String token = TestSessions.signUpToken(mvc);
        var session = TestSessions.bearer(token);
        mvc.perform(get("/api/account").with(session))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.plan").value("FREE"));

        mvc.perform(post("/api/auth/logout").with(session)).andExpect(status().isNoContent());

        mvc.perform(get("/api/account").with(session)).andExpect(status().isUnauthorized());
    }

    @Test
    void la_cle_d_appareil_reconnecte_apres_la_deconnexion_jusqu_a_sa_revocation() throws Exception {
        var session = TestSessions.bearer(TestSessions.signUpToken(mvc));
        String issued = mvc.perform(post("/api/auth/devices").with(session)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"label\":\"Pixel 8\"}"))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String deviceKeyBody = "{\"deviceKey\":\"%s\"}".formatted(JsonPath.<String>read(issued, "$.deviceKey"));
        mvc.perform(post("/api/auth/logout").with(session)).andExpect(status().isNoContent());

        String reconnected = mvc.perform(post("/api/auth/device-login")
                        .contentType(MediaType.APPLICATION_JSON).content(deviceKeyBody))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        var newSession = TestSessions.bearer(JsonPath.read(reconnected, "$.token"));
        mvc.perform(get("/api/account").with(newSession)).andExpect(status().isOk());
        mvc.perform(delete("/api/auth/devices/current").with(newSession)
                        .contentType(MediaType.APPLICATION_JSON).content(deviceKeyBody))
                .andExpect(status().isNoContent());

        mvc.perform(post("/api/auth/device-login")
                        .contentType(MediaType.APPLICATION_JSON).content(deviceKeyBody))
                .andExpect(status().isUnauthorized());
    }

    private UUID upload(RequestPostProcessor session) throws Exception {
        var id = UUID.randomUUID();
        byte[] photo = TestImages.photoOfReceipt(600, 800, 250, 450, 5);
        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", photo))
                        .param("id", id.toString())
                        .with(session))
                .andExpect(status().isAccepted());
        return id;
    }
}
