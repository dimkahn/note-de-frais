package fr.notedefrais.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import fr.notedefrais.account.*;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

@WebMvcTest({AuthController.class, AccountController.class})
class AuthControllerTest {

    static final String PASSWORD = "correct horse battery";

    @Autowired
    MockMvc mvc;
    @MockitoBean
    AccountService service;

    @Test
    void l_inscription_repond_201_avec_le_jeton_et_le_compte() throws Exception {
        given(service.register("alice@example.com", PASSWORD))
                .willReturn(new Authentication("jeton", TestAccounts.free("alice@example.com")));

        mvc.perform(json(post("/api/auth/register"), "alice@example.com", PASSWORD))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.token").value("jeton"))
                .andExpect(jsonPath("$.account.email").value("alice@example.com"))
                .andExpect(jsonPath("$.account.plan").value("FREE"));
    }

    @Test
    void l_inscription_avec_un_e_mail_deja_pris_repond_409() throws Exception {
        given(service.register(any(), any())).willThrow(new EmailAlreadyUsedException());

        mvc.perform(json(post("/api/auth/register"), "alice@example.com", PASSWORD))
                .andExpect(status().isConflict());
    }

    @Test
    void l_inscription_refuse_un_mot_de_passe_de_moins_de_10_caracteres() throws Exception {
        mvc.perform(json(post("/api/auth/register"), "alice@example.com", "123456789"))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @Test
    void l_inscription_refuse_un_e_mail_invalide() throws Exception {
        mvc.perform(json(post("/api/auth/register"), "pas-un-email", PASSWORD))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(service);
    }

    @Test
    void un_mot_de_passe_refuse_par_le_metier_repond_400() throws Exception {
        given(service.register(any(), any())).willThrow(new InvalidPasswordException("trop long"));

        mvc.perform(json(post("/api/auth/register"), "alice@example.com", PASSWORD))
                .andExpect(status().isBadRequest());
    }

    @Test
    void la_connexion_repond_200_avec_le_jeton() throws Exception {
        given(service.login("alice@example.com", PASSWORD))
                .willReturn(new Authentication("jeton", TestAccounts.free("alice@example.com")));

        mvc.perform(json(post("/api/auth/login"), "alice@example.com", PASSWORD))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jeton"))
                .andExpect(jsonPath("$.account.email").value("alice@example.com"));
    }

    @Test
    void une_connexion_refusee_repond_401_avec_un_message_neutre() throws Exception {
        given(service.login(any(), any())).willThrow(new InvalidCredentialsException());

        mvc.perform(json(post("/api/auth/login"), "alice@example.com", "mauvais mot de passe"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.detail").value("E-mail ou mot de passe incorrect"));
    }

    @Test
    void la_deconnexion_revoque_le_jeton_de_la_requete_et_repond_204() throws Exception {
        var accountId = UUID.randomUUID();
        given(service.authenticate("jeton")).willReturn(Optional.of(accountId));

        mvc.perform(post("/api/auth/logout").header("Authorization", "Bearer jeton"))
                .andExpect(status().isNoContent());

        verify(service).logout("jeton");
    }

    @Test
    void le_compte_connecte_est_decrit_par_son_e_mail_et_son_offre() throws Exception {
        var account = TestAccounts.free("alice@example.com");
        given(service.authenticate("jeton")).willReturn(Optional.of(account.getId()));
        given(service.get(account.getId())).willReturn(account);

        mvc.perform(get("/api/account").header("Authorization", "Bearer jeton"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("alice@example.com"))
                .andExpect(jsonPath("$.plan").value("FREE"));
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request, String email,
                                                      String password) {
        return request.contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"%s\",\"password\":\"%s\"}".formatted(email, password));
    }
}
