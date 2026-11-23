package fr.notedefrais;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

/** Branchement de la connexion Google selon la configuration ({@code app.google.client-id}). */
class GoogleSignInFlowTest {

    @Nested
    @SpringBootTest
    @AutoConfigureMockMvc
    class SansIdentifiantClient {

        @Autowired
        MockMvc mvc;

        @Test
        void la_connexion_google_repond_503_en_expliquant_qu_elle_n_est_pas_configuree() throws Exception {
            mvc.perform(googleLogin("jeton-google"))
                    .andExpect(status().isServiceUnavailable())
                    .andExpect(jsonPath("$.detail").value("Connexion Google non configurée sur ce serveur"));
        }
    }

    @Nested
    @SpringBootTest(properties = "app.google.client-id=client-web-de-test.apps.googleusercontent.com")
    @AutoConfigureMockMvc
    class AvecIdentifiantClient {

        @Autowired
        MockMvc mvc;

        @Test
        void un_jeton_qui_n_est_pas_un_jeton_google_repond_401() throws Exception {
            mvc.perform(googleLogin("pas-un-jeton"))
                    .andExpect(status().isUnauthorized());
        }
    }

    private static MockHttpServletRequestBuilder googleLogin(String idToken) {
        return post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                .content("{\"idToken\":\"%s\"}".formatted(idToken));
    }
}
