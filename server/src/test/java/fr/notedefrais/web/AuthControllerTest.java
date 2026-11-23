package fr.notedefrais.web;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

import fr.notedefrais.account.*;
import fr.notedefrais.expense.ExpenseService;
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
    @MockitoBean
    ExpenseService expenses;
    @MockitoBean
    GoogleIdentityVerifier google;

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
    void le_compte_connecte_est_decrit_avec_son_offre_son_usage_son_quota_et_l_analyse_ia() throws Exception {
        var account = TestAccounts.free("alice@example.com");
        given(service.authenticate("jeton")).willReturn(Optional.of(account.getId()));
        given(service.get(account.getId())).willReturn(account);
        given(service.limitsOf(account.getId())).willReturn(new PlanLimits(104_857_600L, false));
        given(expenses.usedBytes(account.getId())).willReturn(44_040_192L);

        mvc.perform(get("/api/account").header("Authorization", "Bearer jeton"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.email").value("alice@example.com"))
                .andExpect(jsonPath("$.plan").value("FREE"))
                .andExpect(jsonPath("$.usedBytes").value(44_040_192L))
                .andExpect(jsonPath("$.quotaBytes").value(104_857_600L))
                .andExpect(jsonPath("$.aiAnalysis").value(false));
    }

    @Test
    void un_compte_connecte_obtient_une_cle_d_appareil_pour_son_libelle() throws Exception {
        var accountId = UUID.randomUUID();
        given(service.authenticate("jeton")).willReturn(Optional.of(accountId));
        given(service.registerDevice(accountId, "Pixel 8")).willReturn("cle-appareil");

        mvc.perform(post("/api/auth/devices").header("Authorization", "Bearer jeton")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"label\":\"Pixel 8\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.deviceKey").value("cle-appareil"));
    }

    @Test
    void une_cle_d_appareil_ne_s_obtient_pas_sans_session() throws Exception {
        mvc.perform(post("/api/auth/devices")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"label\":\"Pixel 8\"}"))
                .andExpect(status().isUnauthorized());

        verify(service, never()).registerDevice(any(), any());
    }

    @Test
    void une_cle_d_appareil_exige_un_libelle() throws Exception {
        given(service.authenticate("jeton")).willReturn(Optional.of(UUID.randomUUID()));

        mvc.perform(post("/api/auth/devices").header("Authorization", "Bearer jeton")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"label\":\" \"}"))
                .andExpect(status().isBadRequest());

        verify(service, never()).registerDevice(any(), any());
    }

    @Test
    void la_connexion_par_cle_d_appareil_repond_200_avec_un_jeton_sans_session_prealable() throws Exception {
        given(service.deviceLogin("cle-appareil"))
                .willReturn(new Authentication("jeton", TestAccounts.free("alice@example.com")));

        mvc.perform(post("/api/auth/device-login")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"deviceKey\":\"cle-appareil\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jeton"))
                .andExpect(jsonPath("$.account.email").value("alice@example.com"));
    }

    @Test
    void une_cle_d_appareil_inconnue_ou_revoquee_repond_401() throws Exception {
        given(service.deviceLogin(any())).willThrow(new InvalidDeviceKeyException());

        mvc.perform(post("/api/auth/device-login")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"deviceKey\":\"revoquee\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void la_revocation_de_la_cle_de_l_appareil_repond_204() throws Exception {
        var accountId = UUID.randomUUID();
        given(service.authenticate("jeton")).willReturn(Optional.of(accountId));

        mvc.perform(delete("/api/auth/devices/current").header("Authorization", "Bearer jeton")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"deviceKey\":\"cle-appareil\"}"))
                .andExpect(status().isNoContent());

        verify(service).revokeDevice(accountId, "cle-appareil");
    }

    @Test
    void la_connexion_google_repond_200_avec_le_jeton_et_le_compte_sans_session_prealable() throws Exception {
        var identity = new GoogleIdentity("sub-alice", "alice@gmail.com", true);
        given(google.verify("jeton-google")).willReturn(identity);
        given(service.googleLogin(identity))
                .willReturn(new Authentication("jeton", TestAccounts.free("alice@gmail.com")));

        mvc.perform(googleLogin("jeton-google"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.token").value("jeton"))
                .andExpect(jsonPath("$.account.email").value("alice@gmail.com"))
                .andExpect(jsonPath("$.account.plan").value("FREE"));
    }

    @Test
    void un_jeton_google_refuse_repond_401_sans_toucher_aux_comptes() throws Exception {
        given(google.verify(any())).willThrow(new InvalidGoogleTokenException());

        mvc.perform(googleLogin("falsifie"))
                .andExpect(status().isUnauthorized());

        verify(service, never()).googleLogin(any());
    }

    @Test
    void la_connexion_google_exige_un_jeton() throws Exception {
        mvc.perform(googleLogin(" "))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(google);
    }

    @Test
    void la_connexion_google_refuse_un_jeton_demesure_sans_l_analyser() throws Exception {
        mvc.perform(googleLogin("x".repeat(4097)))
                .andExpect(status().isBadRequest());

        verifyNoInteractions(google);
    }

    @Test
    void la_connexion_google_non_configuree_repond_503_avec_un_message_clair() throws Exception {
        given(google.verify(any())).willThrow(new GoogleSignInUnavailableException("Connexion Google non configurée"));

        mvc.perform(googleLogin("jeton-google"))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.detail").value("Connexion Google non configurée"));
    }

    @Test
    void une_identite_google_qui_ne_peut_pas_ouvrir_le_compte_repond_403_avec_le_motif() throws Exception {
        var identity = new GoogleIdentity("sub-intrus", "alice@example.com", false);
        given(google.verify("jeton-google")).willReturn(identity);
        given(service.googleLogin(identity)).willThrow(new GoogleAccountRefusedException("E-mail non vérifié"));

        mvc.perform(googleLogin("jeton-google"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.detail").value("E-mail non vérifié"));
    }

    @Test
    void la_connexion_par_mot_de_passe_d_un_compte_google_repond_401_en_invitant_a_utiliser_google() throws Exception {
        given(service.login(any(), any())).willThrow(new PasswordNotSetException());

        mvc.perform(json(post("/api/auth/login"), "alice@gmail.com", PASSWORD))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value("PASSWORD_NOT_SET"))
                .andExpect(jsonPath("$.detail").value(new PasswordNotSetException().getMessage()));
    }

    private static MockHttpServletRequestBuilder googleLogin(String idToken) {
        return post("/api/auth/google").contentType(MediaType.APPLICATION_JSON)
                .content("{\"idToken\":\"%s\"}".formatted(idToken));
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request, String email,
                                                      String password) {
        return request.contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"%s\",\"password\":\"%s\"}".formatted(email, password));
    }
}
