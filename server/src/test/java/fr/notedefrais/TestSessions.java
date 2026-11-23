package fr.notedefrais;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.jayway.jsonpath.JsonPath;
import java.util.UUID;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

/** Ouvre une session réelle (inscription par l'API) pour les tests de bout en bout. */
final class TestSessions {

    private TestSessions() {}

    static RequestPostProcessor signUp(MockMvc mvc) throws Exception {
        String body = mvc.perform(post("/api/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"%s@example.com\",\"password\":\"correct horse battery\"}"
                                .formatted(UUID.randomUUID())))
                .andExpect(status().isCreated())
                .andReturn().getResponse().getContentAsString();
        String token = JsonPath.read(body, "$.token");
        return request -> {
            request.addHeader("Authorization", "Bearer " + token);
            return request;
        };
    }
}
