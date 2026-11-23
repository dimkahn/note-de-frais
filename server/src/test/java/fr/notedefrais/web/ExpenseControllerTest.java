package fr.notedefrais.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import fr.notedefrais.expense.*;
import fr.notedefrais.expense.ExpenseSpecs.Criteria;
import fr.notedefrais.imaging.Quad;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ExpenseController.class)
class ExpenseControllerTest {

    @Autowired
    MockMvc mvc;
    @MockitoBean
    ExpenseService service;

    @Test
    void l_envoi_d_un_justificatif_repond_202_avec_la_depense_en_attente() throws Exception {
        var id = UUID.randomUUID();
        given(service.register(eq(id), any(), eq("image/jpeg"), eq(ImageFilter.SCAN_BW), eq(null))).willReturn(new Expense(id));

        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", new byte[]{1, 2}))
                        .param("id", id.toString())
                        .param("filter", "SCAN_BW"))
                .andExpect(status().isAccepted())
                .andExpect(header().string("Location", "/api/expenses/" + id))
                .andExpect(jsonPath("$.id").value(id.toString()))
                .andExpect(jsonPath("$.status").value("PENDING"));
    }

    @Test
    void transmet_les_coins_choisis_sur_l_appareil() throws Exception {
        var id = UUID.randomUUID();
        var quad = Quad.parse("0.1,0.1,0.9,0.1,0.9,0.9,0.1,0.9");
        given(service.register(eq(id), any(), eq("image/jpeg"), any(), eq(quad))).willReturn(new Expense(id));

        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", new byte[]{1}))
                        .param("id", id.toString())
                        .param("corners", quad.format()))
                .andExpect(status().isAccepted());
    }

    @Test
    void refuse_des_coins_invalides() throws Exception {
        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "ticket.jpg", "image/jpeg", new byte[]{1}))
                        .param("corners", "0,0,1,1,1,0,0,1"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void refuse_un_fichier_qui_n_est_pas_une_image() throws Exception {
        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "x.pdf", "application/pdf", new byte[]{1})))
                .andExpect(status().isUnsupportedMediaType());
    }

    @Test
    void refuse_un_fichier_vide() throws Exception {
        mvc.perform(multipart("/api/expenses")
                        .file(new MockMultipartFile("file", "x.jpg", "image/jpeg", new byte[0])))
                .andExpect(status().isBadRequest());
    }

    @Test
    void recherche_avec_criteres() throws Exception {
        var e = new Expense(UUID.randomUUID());
        e.setMerchant("Ibis");
        e.setAmountTotal(new BigDecimal("89.00"));
        e.setExpenseDate(LocalDate.of(2026, 3, 11));
        var criteria = new Criteria(Category.HOTEL, "Lyon", null, null, LocalDate.of(2026, 3, 1), null, null);
        given(service.search(criteria)).willReturn(List.of(e));

        mvc.perform(get("/api/expenses").param("category", "HOTEL").param("city", "Lyon").param("from", "2026-03-01"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].merchant").value("Ibis"))
                .andExpect(jsonPath("$[0].amountTotal").value(89.00))
                .andExpect(jsonPath("$[0].expenseDate").value("2026-03-11"));
    }

    @Test
    void synthese_par_critere() throws Exception {
        given(service.summary(any(), eq(ExpenseSummary.GroupBy.CITY)))
                .willReturn(List.of(new ExpenseSummary.Group("Lyon", 2, Map.of("EUR", new BigDecimal("100.00")))));

        mvc.perform(get("/api/expenses/summary").param("groupBy", "CITY"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].key").value("Lyon"))
                .andExpect(jsonPath("$[0].count").value(2))
                .andExpect(jsonPath("$[0].totals.EUR").value(100.00));
    }

    @Test
    void une_depense_inconnue_repond_404() throws Exception {
        var id = UUID.randomUUID();
        given(service.get(id)).willThrow(new ExpenseNotFoundException(id));

        mvc.perform(get("/api/expenses/{id}", id)).andExpect(status().isNotFound());
    }

    @Test
    void la_modification_valide_les_champs() throws Exception {
        mvc.perform(put("/api/expenses/{id}", UUID.randomUUID())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"currency\":\"euros\"}"))
                .andExpect(status().isBadRequest());
    }

    @Test
    void la_modification_est_transmise_au_service() throws Exception {
        var id = UUID.randomUUID();
        given(service.update(eq(id), any())).willReturn(new Expense(id));

        mvc.perform(put("/api/expenses/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"merchant\":\"Ibis\",\"category\":\"HOTEL\",\"amountTotal\":89.00,\"currency\":\"EUR\"}"))
                .andExpect(status().isOk());

        verify(service).update(eq(id), eq(new ExpenseUpdate("Ibis", Category.HOTEL, null,
                new BigDecimal("89.00"), null, "EUR", null, null, null, null, null)));
    }

    @Test
    void les_montants_peuvent_etre_envoyes_en_texte_decimal_exact() throws Exception {
        var id = UUID.randomUUID();
        given(service.update(eq(id), any())).willReturn(new Expense(id));

        mvc.perform(put("/api/expenses/{id}", id)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"amountTotal\":\"0.10\",\"expenseDate\":\"2026-03-10\"}"))
                .andExpect(status().isOk());

        verify(service).update(eq(id), eq(new ExpenseUpdate(null, null, LocalDate.of(2026, 3, 10),
                new BigDecimal("0.10"), null, null, null, null, null, null, null)));
    }

    @Test
    void l_original_est_servi_avec_son_type() throws Exception {
        var id = UUID.randomUUID();
        var e = new Expense(id);
        e.setOriginalContentType("image/png");
        given(service.get(id)).willReturn(e);
        given(service.original(id)).willReturn(new byte[]{7});

        mvc.perform(get("/api/expenses/{id}/original", id))
                .andExpect(status().isOk())
                .andExpect(content().contentType("image/png"))
                .andExpect(content().bytes(new byte[]{7}));
    }

    @Test
    void la_suppression_repond_204() throws Exception {
        var id = UUID.randomUUID();

        mvc.perform(delete("/api/expenses/{id}", id)).andExpect(status().isNoContent());

        verify(service).delete(id);
    }
}
