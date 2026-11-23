package fr.notedefrais;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

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

/** Coutures réelles des documents : session, contrôleur, service, base, stockage et quota partagé. */
@SpringBootTest(properties = "app.plans.free.quota=1KB")
@AutoConfigureMockMvc
class DocumentFlowTest {

    static final byte[] PAGE_PHOTO = new byte[600];
    static final byte[] PAGE_RENDER = new byte[300];

    @Autowired
    MockMvc mvc;

    @Test
    void l_api_des_documents_repond_401_sans_session() throws Exception {
        mvc.perform(get("/api/documents/changes").param("since", "2000-01-01T00:00:00Z"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void un_document_envoye_par_un_appareil_est_recupere_avec_ses_fichiers() throws Exception {
        var session = TestSessions.signUp(mvc);
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();

        save(session, id, pageId).andExpect(status().isOk());
        addPage(session, id, pageId).andExpect(status().isOk());

        mvc.perform(get("/api/documents/changes").param("since", "2000-01-01T00:00:00Z").with(session))
                .andExpect(jsonPath("$[0].id").value(id.toString()))
                .andExpect(jsonPath("$[0].pages[0].id").value(pageId.toString()));
        mvc.perform(get("/api/documents/{id}/pages/{pageId}/original", id, pageId).with(session))
                .andExpect(content().bytes(PAGE_PHOTO));
        mvc.perform(get("/api/account").with(session))
                .andExpect(jsonPath("$.usedBytes").value(PAGE_PHOTO.length + PAGE_RENDER.length));
    }

    @Test
    void un_compte_n_accede_jamais_au_document_d_un_autre() throws Exception {
        var alice = TestSessions.signUp(mvc);
        var bob = TestSessions.signUp(mvc);
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        save(alice, id, pageId);
        addPage(alice, id, pageId);

        mvc.perform(get("/api/documents/{id}", id).with(bob)).andExpect(status().isNotFound());
        mvc.perform(get("/api/documents/{id}/pages/{pageId}/original", id, pageId).with(bob))
                .andExpect(status().isNotFound());
        mvc.perform(get("/api/documents/{id}/pages/{pageId}/processed", id, pageId).with(bob))
                .andExpect(status().isNotFound());
        save(bob, id, pageId).andExpect(status().isNotFound());
        addPage(bob, id, UUID.randomUUID()).andExpect(status().isNotFound());
        mvc.perform(delete("/api/documents/{id}", id).with(bob)).andExpect(status().isNotFound());
        mvc.perform(get("/api/documents/changes").param("since", "2000-01-01T00:00:00Z").with(bob))
                .andExpect(jsonPath("$.length()").value(0));

        mvc.perform(get("/api/documents/{id}", id).with(alice))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.deleted").value(false));
    }

    @Test
    void les_documents_comptent_dans_le_quota_des_depenses_et_inversement() throws Exception {
        var session = TestSessions.signUp(mvc);
        var id = UUID.randomUUID();
        var pageId = UUID.randomUUID();
        save(session, id, pageId);
        addPage(session, id, pageId).andExpect(status().isOk());

        mvc.perform(multipart("/api/expenses").with(session)
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", new byte[200])))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"));
        addPage(session, id, UUID.randomUUID())
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.usedBytes").value(PAGE_PHOTO.length + PAGE_RENDER.length));

        mvc.perform(delete("/api/documents/{id}", id).with(session)).andExpect(status().isNoContent());
        mvc.perform(get("/api/account").with(session)).andExpect(jsonPath("$.usedBytes").value(0));
    }

    private ResultActions save(RequestPostProcessor session, UUID id, UUID pageId) throws Exception {
        return mvc.perform(put("/api/documents/{id}", id).with(session).contentType(MediaType.APPLICATION_JSON)
                .content("{\"title\":\"Bail\",\"pageIds\":[\"%s\"]}".formatted(pageId)));
    }

    private ResultActions addPage(RequestPostProcessor session, UUID id, UUID pageId) throws Exception {
        return mvc.perform(multipart("/api/documents/{id}/pages", id).with(session)
                .file(new MockMultipartFile("original", "page.jpg", "image/jpeg", PAGE_PHOTO))
                .file(new MockMultipartFile("processed", "rendu.jpg", "image/jpeg", PAGE_RENDER))
                .param("pageId", pageId.toString())
                .param("filter", "SCAN_BW"));
    }
}
