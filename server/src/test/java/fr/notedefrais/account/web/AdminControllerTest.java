package fr.notedefrais.account.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import fr.notedefrais.account.AccountNotFoundException;
import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.Plan;
import fr.notedefrais.account.TestAccounts;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@WebMvcTest(AdminController.class)
@TestPropertySource(properties = "app.api-token=secret-admin")
class AdminControllerTest {

    @Autowired
    MockMvc mvc;
    @MockitoBean
    AccountService service;

    @Test
    void l_administration_attribue_une_offre_a_un_compte_par_son_e_mail() throws Exception {
        var account = TestAccounts.free("alice@example.com");
        given(service.changePlan("alice@example.com", Plan.PREMIUM)).willReturn(account);

        mvc.perform(changePlan("alice@example.com", "{\"plan\":\"PREMIUM\"}").header("X-Api-Token", "secret-admin"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("alice@example.com"));

        verify(service).changePlan("alice@example.com", Plan.PREMIUM);
    }

    @Test
    void changer_une_offre_exige_le_jeton_d_administration() throws Exception {
        mvc.perform(changePlan("alice@example.com", "{\"plan\":\"PREMIUM\"}").header("Authorization", "Bearer jeton"))
                .andExpect(status().isUnauthorized());

        verify(service, never()).changePlan(any(), any());
    }

    @Test
    void changer_l_offre_d_un_compte_inconnu_repond_404() throws Exception {
        given(service.changePlan(any(), any())).willThrow(new AccountNotFoundException("inconnu@example.com"));

        mvc.perform(changePlan("inconnu@example.com", "{\"plan\":\"PREMIUM\"}").header("X-Api-Token", "secret-admin"))
                .andExpect(status().isNotFound());
    }

    @Test
    void changer_une_offre_exige_une_offre_valide() throws Exception {
        mvc.perform(changePlan("alice@example.com", "{}").header("X-Api-Token", "secret-admin"))
                .andExpect(status().isBadRequest());

        verify(service, never()).changePlan(any(), any());
    }

    private static MockHttpServletRequestBuilder changePlan(String email, String body) {
        return put("/api/admin/accounts/{email}/plan", email).contentType(MediaType.APPLICATION_JSON).content(body);
    }
}
