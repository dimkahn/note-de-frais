package fr.notedefrais.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.QuotaExceededException;
import fr.notedefrais.document.Document;
import fr.notedefrais.document.DocumentContent;
import fr.notedefrais.document.DocumentNotFoundException;
import fr.notedefrais.document.DocumentPage;
import fr.notedefrais.document.DocumentService;
import fr.notedefrais.expense.ImageFilter;
import fr.notedefrais.imaging.Quad;
import java.time.Instant;
import java.util.Arrays;
import java.util.List;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockMultipartHttpServletRequestBuilder;
import org.springframework.test.web.servlet.request.RequestPostProcessor;

@WebMvcTest(DocumentController.class)
class DocumentControllerTest {

    static final UUID OWNER = UUID.randomUUID();
    static final UUID DOC = UUID.randomUUID();
    static final UUID PAGE = UUID.randomUUID();
    static final Quad CORNERS = Quad.parse("0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9");
    static final RequestPostProcessor SESSION = request -> {
        request.addHeader("Authorization", "Bearer jeton");
        return request;
    };

    @Autowired
    MockMvc mvc;
    @MockitoBean
    DocumentService service;
    @MockitoBean
    AccountService accounts;

    @BeforeEach
    void authenticate() {
        given(accounts.authenticate("jeton")).willReturn(Optional.of(OWNER));
    }

    @Test
    void l_enregistrement_d_un_document_rend_son_titre_et_ses_pages_dans_l_ordre() throws Exception {
        given(service.save(OWNER, DOC, "Bail", List.of(PAGE)))
                .willReturn(new DocumentContent(new Document(DOC, OWNER, "Bail"), List.of(page())));

        mvc.perform(put("/api/documents/{id}", DOC).with(SESSION).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Bail\",\"pageIds\":[\"%s\"]}".formatted(PAGE)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(DOC.toString()))
                .andExpect(jsonPath("$.title").value("Bail"))
                .andExpect(jsonPath("$.deleted").value(false))
                .andExpect(jsonPath("$.pages[0].id").value(PAGE.toString()))
                .andExpect(jsonPath("$.pages[0].filter").value("SCAN_BW"))
                .andExpect(jsonPath("$.pages[0].corners").value(CORNERS.format()))
                .andExpect(jsonPath("$.pages[0].renderVersion").value(1));
    }

    @Test
    void refuse_un_titre_vide_ou_une_liste_de_pages_absente() throws Exception {
        mvc.perform(put("/api/documents/{id}", DOC).with(SESSION).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\" \",\"pageIds\":[]}"))
                .andExpect(status().isBadRequest());
        mvc.perform(put("/api/documents/{id}", DOC).with(SESSION).contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"Bail\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void un_document_introuvable_repond_404() throws Exception {
        given(service.get(OWNER, DOC)).willThrow(new DocumentNotFoundException(DOC));

        mvc.perform(get("/api/documents/{id}", DOC).with(SESSION)).andExpect(status().isNotFound());
    }

    @Test
    void l_envoi_d_une_page_transmet_l_original_le_rendu_le_filtre_et_le_contour() throws Exception {
        given(service.addPage(eq(OWNER), eq(DOC), any())).willReturn(page());

        mvc.perform(pageUpload("image/png", "image/jpeg").param("pageId", PAGE.toString()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(PAGE.toString()))
                .andExpect(jsonPath("$.renderVersion").value(1));

        verify(service).addPage(eq(OWNER), eq(DOC), argThat(p -> p.id().equals(PAGE)
                && Arrays.equals(p.original(), new byte[]{1}) && "image/png".equals(p.originalContentType())
                && Arrays.equals(p.processed(), new byte[]{2})
                && p.filter() == ImageFilter.SCAN_BW && CORNERS.equals(p.corners())));
    }

    @Test
    void refuse_une_page_sans_identifiant_ni_filtre_ou_dont_les_fichiers_ne_sont_pas_des_images() throws Exception {
        mvc.perform(pageUpload("image/jpeg", "image/jpeg")).andExpect(status().isBadRequest());
        mvc.perform(pageUpload("application/pdf", "image/jpeg").param("pageId", PAGE.toString()))
                .andExpect(status().isUnsupportedMediaType());
        mvc.perform(pageUpload("image/jpeg", "image/png").param("pageId", PAGE.toString()))
                .andExpect(status().isUnsupportedMediaType());
        mvc.perform(multipart("/api/documents/{id}/pages", DOC).with(SESSION)
                        .file(new MockMultipartFile("original", "page", "image/jpeg", new byte[]{1}))
                        .file(new MockMultipartFile("processed", "rendu", "image/jpeg", new byte[]{2}))
                        .param("pageId", PAGE.toString()))
                .andExpect(status().isBadRequest());
    }

    @Test
    void une_page_au_dela_du_quota_repond_403_quota_exceeded() throws Exception {
        given(service.addPage(eq(OWNER), eq(DOC), any())).willThrow(new QuotaExceededException(10, 12));

        mvc.perform(pageUpload("image/jpeg", "image/jpeg").param("pageId", PAGE.toString()))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value("QUOTA_EXCEEDED"))
                .andExpect(jsonPath("$.usedBytes").value(10));
    }

    @Test
    void un_nouveau_rendu_remplace_celui_de_la_page() throws Exception {
        given(service.replaceRender(eq(OWNER), eq(DOC), eq(PAGE), any(), eq(ImageFilter.SHARPEN), eq(CORNERS)))
                .willReturn(page());

        mvc.perform(multipart("/api/documents/{id}/pages/{pageId}/processed", DOC, PAGE).with(SESSION)
                        .file(new MockMultipartFile("processed", "rendu.jpg", "image/jpeg", new byte[]{3}))
                        .param("filter", "SHARPEN")
                        .param("corners", CORNERS.format()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(PAGE.toString()));
    }

    @Test
    void la_suppression_repond_204() throws Exception {
        mvc.perform(delete("/api/documents/{id}", DOC).with(SESSION)).andExpect(status().isNoContent());

        verify(service).delete(OWNER, DOC);
    }

    @Test
    void les_changements_depuis_une_date_sont_listes() throws Exception {
        var since = Instant.parse("2026-11-01T00:00:00Z");
        given(service.changesSince(OWNER, since))
                .willReturn(List.of(new DocumentContent(new Document(DOC, OWNER, "Bail"), List.of())));

        mvc.perform(get("/api/documents/changes").param("since", since.toString()).with(SESSION))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].id").value(DOC.toString()));
    }

    @Test
    void l_original_d_une_page_est_servi_avec_son_type() throws Exception {
        given(service.page(OWNER, DOC, PAGE)).willReturn(page());
        given(service.original(OWNER, DOC, PAGE)).willReturn(new byte[]{1, 2});

        mvc.perform(get("/api/documents/{id}/pages/{pageId}/original", DOC, PAGE).with(SESSION))
                .andExpect(status().isOk())
                .andExpect(content().contentType("image/png"))
                .andExpect(content().bytes(new byte[]{1, 2}));
    }

    @Test
    void le_rendu_d_une_page_est_servi_en_jpeg() throws Exception {
        given(service.processed(OWNER, DOC, PAGE)).willReturn(new byte[]{3});

        mvc.perform(get("/api/documents/{id}/pages/{pageId}/processed", DOC, PAGE).with(SESSION))
                .andExpect(status().isOk())
                .andExpect(content().contentType(MediaType.IMAGE_JPEG))
                .andExpect(content().bytes(new byte[]{3}));
    }

    private static MockMultipartHttpServletRequestBuilder pageUpload(String originalType, String processedType) {
        return (MockMultipartHttpServletRequestBuilder) multipart("/api/documents/{id}/pages", DOC).with(SESSION)
                .file(new MockMultipartFile("original", "page", originalType, new byte[]{1}))
                .file(new MockMultipartFile("processed", "rendu", processedType, new byte[]{2}))
                .param("filter", "SCAN_BW")
                .param("corners", CORNERS.format());
    }

    private static DocumentPage page() {
        var page = new DocumentPage(PAGE, DOC, OWNER, "original.png", "image/png", 1);
        page.render("processed.jpg", 1, ImageFilter.SCAN_BW, CORNERS.format());
        return page;
    }
}
