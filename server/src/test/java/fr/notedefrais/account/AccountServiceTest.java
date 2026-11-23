package fr.notedefrais.account;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Map;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

@DataJpaTest
class AccountServiceTest {

    static final String PASSWORD = "correct horse battery";
    static final Instant NOW = Instant.parse("2026-11-23T10:00:00Z");
    static final Duration TTL = Duration.ofDays(30);
    static final PlanLimits FREE_LIMITS = new PlanLimits(100L * 1024 * 1024, false);
    static final PlanLimits PREMIUM_LIMITS = new PlanLimits(1024L * 1024 * 1024, true);

    @Autowired
    AccountRepository accounts;
    @Autowired
    SessionRepository sessions;
    @Autowired
    DeviceKeyRepository devices;

    // Coût minimal : le test vérifie le comportement, pas la robustesse du hash.
    final BCryptPasswordEncoder encoder = new BCryptPasswordEncoder(4);
    AccountService service;

    @BeforeEach
    void setUp() {
        service = serviceAt(NOW);
    }

    @Test
    void l_inscription_stocke_un_hash_du_mot_de_passe_et_jamais_le_mot_de_passe() {
        Authentication auth = service.register("alice@example.com", PASSWORD);

        Account stored = accounts.findById(auth.account().getId()).orElseThrow();
        assertThat(stored.getPasswordHash()).isNotEqualTo(PASSWORD);
        assertThat(encoder.matches(PASSWORD, stored.getPasswordHash())).isTrue();
    }

    @Test
    void l_e_mail_est_normalise_en_minuscules() {
        Authentication auth = service.register("  Alice@Example.COM ", PASSWORD);

        assertThat(auth.account().getEmail()).isEqualTo("alice@example.com");
    }

    @Test
    void un_nouveau_compte_est_en_offre_gratuite() {
        Authentication auth = service.register("alice@example.com", PASSWORD);

        assertThat(auth.account().getPlan()).isEqualTo(Plan.FREE);
    }

    @Test
    void refuse_un_e_mail_deja_pris_quelle_que_soit_la_casse() {
        service.register("alice@example.com", PASSWORD);

        assertThatThrownBy(() -> service.register("ALICE@example.com", "un autre mot de passe"))
                .isInstanceOf(EmailAlreadyUsedException.class);
    }

    @Test
    void refuse_un_mot_de_passe_au_dela_de_la_limite_de_bcrypt() {
        String seventyThreeBytes = "é".repeat(36) + "x"; // 37 caractères mais 73 octets en UTF-8

        assertThatThrownBy(() -> service.register("alice@example.com", seventyThreeBytes))
                .isInstanceOf(InvalidPasswordException.class);
    }

    @Test
    void le_jeton_rendu_a_l_inscription_authentifie_le_compte() {
        Authentication auth = service.register("alice@example.com", PASSWORD);

        assertThat(service.authenticate(auth.token())).contains(auth.account().getId());
    }

    @Test
    void la_connexion_rend_un_jeton_qui_authentifie_le_compte() {
        var registered = service.register("alice@example.com", PASSWORD);

        Authentication auth = service.login("Alice@example.com", PASSWORD);

        assertThat(auth.account().getId()).isEqualTo(registered.account().getId());
        assertThat(service.authenticate(auth.token())).contains(registered.account().getId());
    }

    @Test
    void la_connexion_echoue_avec_le_meme_message_pour_un_mauvais_mot_de_passe_ou_un_e_mail_inconnu() {
        service.register("alice@example.com", PASSWORD);

        var wrongPassword = catchThrowableOfType(InvalidCredentialsException.class,
                () -> service.login("alice@example.com", "mauvais mot de passe"));
        var unknownEmail = catchThrowableOfType(InvalidCredentialsException.class,
                () -> service.login("bob@example.com", PASSWORD));

        assertThat(wrongPassword.getMessage()).isEqualTo(unknownEmail.getMessage());
    }

    @Test
    void seul_le_hash_sha256_du_jeton_est_stocke() throws Exception {
        Authentication auth = service.register("alice@example.com", PASSWORD);

        String expectedHash = HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(auth.token().getBytes(StandardCharsets.UTF_8)));
        assertThat(sessions.findAll()).extracting(Session::getTokenHash).containsExactly(expectedHash);
    }

    @Test
    void le_jeton_fait_256_bits_aleatoires() {
        String first = service.register("alice@example.com", PASSWORD).token();
        String second = service.login("alice@example.com", PASSWORD).token();

        assertThat(first).isNotEqualTo(second);
        assertThat(Base64.getUrlDecoder().decode(first)).hasSize(32);
    }

    @Test
    void un_jeton_expire_est_refuse() {
        String token = service.register("alice@example.com", PASSWORD).token();

        var later = serviceAt(NOW.plus(TTL));

        assertThat(later.authenticate(token)).isEmpty();
    }

    @Test
    void un_jeton_encore_valide_juste_avant_l_expiration_est_accepte() {
        String token = service.register("alice@example.com", PASSWORD).token();

        var later = serviceAt(NOW.plus(TTL).minusSeconds(1));

        assertThat(later.authenticate(token)).isPresent();
    }

    @Test
    void la_deconnexion_revoque_le_jeton() {
        String token = service.register("alice@example.com", PASSWORD).token();

        service.logout(token);

        assertThat(service.authenticate(token)).isEmpty();
    }

    @Test
    void un_jeton_inconnu_est_refuse() {
        assertThat(service.authenticate("inconnu")).isEmpty();
    }

    @Test
    void retrouve_un_compte_par_son_identifiant() {
        var registered = service.register("alice@example.com", PASSWORD).account();

        Account found = service.get(registered.getId());

        assertThat(found.getEmail()).isEqualTo("alice@example.com");
        assertThat(found.getPlan()).isEqualTo(Plan.FREE);
    }

    @Test
    void la_cle_d_appareil_ouvre_une_nouvelle_session_du_compte() {
        var alice = service.register("alice@example.com", PASSWORD).account();
        String deviceKey = service.registerDevice(alice.getId(), "Pixel 8");

        Authentication auth = service.deviceLogin(deviceKey);

        assertThat(auth.account().getId()).isEqualTo(alice.getId());
        assertThat(service.authenticate(auth.token())).contains(alice.getId());
    }

    @Test
    void seul_le_hash_sha256_de_la_cle_d_appareil_est_stocke_avec_son_libelle() throws Exception {
        var alice = service.register("alice@example.com", PASSWORD).account();

        String deviceKey = service.registerDevice(alice.getId(), "Pixel 8");

        String expectedHash = HexFormat.of().formatHex(
                MessageDigest.getInstance("SHA-256").digest(deviceKey.getBytes(StandardCharsets.UTF_8)));
        assertThat(devices.findAll()).singleElement().satisfies(device -> {
            assertThat(device.getKeyHash()).isEqualTo(expectedHash);
            assertThat(device.getAccountId()).isEqualTo(alice.getId());
            assertThat(device.getLabel()).isEqualTo("Pixel 8");
            assertThat(device.getCreatedAt()).isEqualTo(NOW);
        });
    }

    @Test
    void la_cle_d_appareil_fait_256_bits_aleatoires() {
        var alice = service.register("alice@example.com", PASSWORD).account();

        String first = service.registerDevice(alice.getId(), "Pixel 8");
        String second = service.registerDevice(alice.getId(), "Tablette");

        assertThat(first).isNotEqualTo(second);
        assertThat(Base64.getUrlDecoder().decode(first)).hasSize(32);
    }

    @Test
    void une_cle_d_appareil_inconnue_est_refusee() {
        assertThatThrownBy(() -> service.deviceLogin("inconnue"))
                .isInstanceOf(InvalidDeviceKeyException.class);
    }

    @Test
    void une_cle_d_appareil_revoquee_est_refusee() {
        var alice = service.register("alice@example.com", PASSWORD).account();
        String deviceKey = service.registerDevice(alice.getId(), "Pixel 8");

        service.revokeDevice(alice.getId(), deviceKey);

        assertThatThrownBy(() -> service.deviceLogin(deviceKey))
                .isInstanceOf(InvalidDeviceKeyException.class);
    }

    @Test
    void un_compte_ne_peut_pas_revoquer_la_cle_d_appareil_d_un_autre() {
        var alice = service.register("alice@example.com", PASSWORD).account();
        var bob = service.register("bob@example.com", PASSWORD).account();
        String deviceKey = service.registerDevice(alice.getId(), "Pixel 8");

        service.revokeDevice(bob.getId(), deviceKey);

        assertThat(service.deviceLogin(deviceKey).account().getId()).isEqualTo(alice.getId());
    }

    @Test
    void la_deconnexion_conserve_la_cle_d_appareil() {
        var auth = service.register("alice@example.com", PASSWORD);
        String deviceKey = service.registerDevice(auth.account().getId(), "Pixel 8");

        service.logout(auth.token());

        assertThat(service.deviceLogin(deviceKey).account().getId()).isEqualTo(auth.account().getId());
    }

    @Test
    void les_limites_d_un_compte_sont_celles_de_son_offre() {
        var alice = service.register("alice@example.com", PASSWORD).account();

        PlanLimits limits = service.limitsOf(alice.getId());

        assertThat(limits).isEqualTo(FREE_LIMITS);
    }

    @Test
    void l_administration_fait_passer_un_compte_en_premium_par_son_e_mail() {
        var alice = service.register("alice@example.com", PASSWORD).account();

        Account changed = service.changePlan(" Alice@Example.com", Plan.PREMIUM);

        assertThat(changed.getPlan()).isEqualTo(Plan.PREMIUM);
        assertThat(service.limitsOf(alice.getId())).isEqualTo(PREMIUM_LIMITS);
    }

    @Test
    void changer_l_offre_d_un_compte_inconnu_leve_une_erreur_explicite() {
        assertThatThrownBy(() -> service.changePlan("inconnu@example.com", Plan.PREMIUM))
                .isInstanceOf(AccountNotFoundException.class);
    }

    @Test
    void chaque_offre_doit_avoir_ses_limites_configurees() {
        assertThatThrownBy(() -> new AccountService(accounts, sessions, devices, encoder, Clock.systemUTC(), TTL,
                Map.of(Plan.FREE, FREE_LIMITS)))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("PREMIUM");
    }

    @Test
    void la_connexion_google_d_un_inconnu_cree_un_compte_gratuit_sans_mot_de_passe() {
        Authentication auth = service.googleLogin(new GoogleIdentity("sub-alice", "Alice@Gmail.com", true));

        Account created = accounts.findById(auth.account().getId()).orElseThrow();
        assertThat(created.getEmail()).isEqualTo("alice@gmail.com");
        assertThat(created.getPlan()).isEqualTo(Plan.FREE);
        assertThat(created.getPasswordHash()).isNull();
        assertThat(created.getGoogleSubject()).isEqualTo("sub-alice");
        assertThat(service.authenticate(auth.token())).contains(created.getId());
    }

    @Test
    void la_connexion_google_retrouve_le_compte_par_son_identifiant_google_meme_si_l_e_mail_a_change() {
        var alice = service.googleLogin(new GoogleIdentity("sub-alice", "alice@gmail.com", true)).account();

        Authentication auth = service.googleLogin(new GoogleIdentity("sub-alice", "alice.nouvelle@gmail.com", false));

        assertThat(auth.account().getId()).isEqualTo(alice.getId());
        assertThat(accounts.count()).isEqualTo(1);
    }

    @Test
    void la_connexion_google_lie_le_compte_e_mail_existant_quand_l_e_mail_google_est_verifie() {
        var alice = service.register("alice@example.com", PASSWORD).account();

        Authentication auth = service.googleLogin(new GoogleIdentity("sub-alice", "Alice@example.com", true));

        assertThat(auth.account().getId()).isEqualTo(alice.getId());
        assertThat(accounts.findById(alice.getId()).orElseThrow().getGoogleSubject()).isEqualTo("sub-alice");
        assertThat(service.authenticate(auth.token())).contains(alice.getId());
    }

    /** L'inscription ne vérifie pas l'e-mail : un compte pré-créé par un tiers ne doit pas lui rester accessible. */
    @Test
    void la_liaison_a_google_retire_le_mot_de_passe_les_sessions_et_les_cles_d_appareil_anterieures() {
        var registered = service.register("alice@example.com", PASSWORD);
        String deviceKey = service.registerDevice(registered.account().getId(), "Pixel 8");

        service.googleLogin(new GoogleIdentity("sub-alice", "alice@example.com", true));

        assertThatThrownBy(() -> service.login("alice@example.com", PASSWORD))
                .isInstanceOf(PasswordNotSetException.class);
        assertThat(service.authenticate(registered.token())).isEmpty();
        assertThatThrownBy(() -> service.deviceLogin(deviceKey)).isInstanceOf(InvalidDeviceKeyException.class);
    }

    @Test
    void refuse_la_connexion_google_dont_l_e_mail_non_verifie_correspond_a_un_compte_existant() {
        var alice = service.register("alice@example.com", PASSWORD).account();

        assertThatThrownBy(() -> service.googleLogin(new GoogleIdentity("sub-intrus", "alice@example.com", false)))
                .isInstanceOf(GoogleAccountRefusedException.class);
        assertThat(accounts.findById(alice.getId()).orElseThrow().getGoogleSubject()).isNull();
    }

    @Test
    void refuse_de_creer_un_compte_google_avec_un_e_mail_non_verifie() {
        assertThatThrownBy(() -> service.googleLogin(new GoogleIdentity("sub-bob", "bob@example.com", false)))
                .isInstanceOf(GoogleAccountRefusedException.class);
        assertThat(accounts.count()).isZero();
    }

    @Test
    void refuse_de_lier_un_compte_deja_lie_a_un_autre_compte_google() {
        var alice = service.googleLogin(new GoogleIdentity("sub-alice", "alice@gmail.com", true)).account();

        assertThatThrownBy(() -> service.googleLogin(new GoogleIdentity("sub-autre", "alice@gmail.com", true)))
                .isInstanceOf(GoogleAccountRefusedException.class);
        assertThat(accounts.findById(alice.getId()).orElseThrow().getGoogleSubject()).isEqualTo("sub-alice");
    }

    @Test
    void un_compte_cree_par_google_ne_se_connecte_pas_par_mot_de_passe_et_l_explique() {
        service.googleLogin(new GoogleIdentity("sub-alice", "alice@gmail.com", true));

        assertThatThrownBy(() -> service.login("alice@gmail.com", PASSWORD))
                .isInstanceOf(PasswordNotSetException.class)
                .hasMessageContaining("Google");
    }

    private AccountService serviceAt(Instant now) {
        return new AccountService(accounts, sessions, devices, encoder, Clock.fixed(now, ZoneOffset.UTC), TTL,
                Map.of(Plan.FREE, FREE_LIMITS, Plan.PREMIUM, PREMIUM_LIMITS));
    }
}
