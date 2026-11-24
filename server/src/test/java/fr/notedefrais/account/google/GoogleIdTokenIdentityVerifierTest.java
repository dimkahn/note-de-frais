package fr.notedefrais.account.google;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.http.HttpTransport;
import com.google.api.client.http.LowLevelHttpRequest;
import com.google.api.client.json.gson.GsonFactory;
import com.google.api.client.json.webtoken.JsonWebSignature;
import com.google.api.client.testing.http.MockHttpTransport;
import com.google.api.client.testing.http.MockLowLevelHttpResponse;
import fr.notedefrais.account.GoogleIdentity;
import fr.notedefrais.account.GoogleSignInUnavailableException;
import fr.notedefrais.account.InvalidGoogleTokenException;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPairGenerator;
import java.security.KeyStore;
import java.security.PrivateKey;
import java.security.cert.Certificate;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Map;
import java.util.function.Consumer;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/**
 * La bibliothèque Google est exercée pour de vrai ; seule la frontière réseau (les certificats publics
 * de Google) est simulée, avec une clé de test générée par {@code keytool} à chaque exécution.
 */
class GoogleIdTokenIdentityVerifierTest {

    static final String CLIENT_ID = "client-web-de-test.apps.googleusercontent.com";
    static final String KEY_ID = "cle-de-test";
    static final char[] STORE_PASSWORD = "mot-de-passe-de-test".toCharArray();

    static PrivateKey googleKey;
    static String googleCertificates;

    @BeforeAll
    static void generateTestSigningKey(@TempDir Path dir) throws Exception {
        Path store = dir.resolve("google-test.p12");
        Process keytool = new ProcessBuilder(Path.of(System.getProperty("java.home"), "bin", "keytool").toString(),
                "-genkeypair", "-keyalg", "RSA", "-keysize", "2048", "-alias", KEY_ID, "-dname", "CN=test",
                "-validity", "1", "-storetype", "PKCS12", "-keystore", store.toString(),
                "-storepass", new String(STORE_PASSWORD)).redirectErrorStream(true).start();
        assertThat(keytool.waitFor()).as(new String(keytool.getInputStream().readAllBytes())).isZero();
        KeyStore keyStore = KeyStore.getInstance("PKCS12");
        try (InputStream in = Files.newInputStream(store)) {
            keyStore.load(in, STORE_PASSWORD);
        }
        googleKey = (PrivateKey) keyStore.getKey(KEY_ID, STORE_PASSWORD);
        googleCertificates = publishedCertificates(keyStore.getCertificate(KEY_ID));
    }

    final GoogleIdTokenIdentityVerifier verifier =
            new GoogleIdTokenIdentityVerifier(CLIENT_ID, certificatesEndpoint(googleCertificates));

    @Test
    void rend_l_identite_d_un_jeton_signe_par_google_pour_cette_application() throws Exception {
        String idToken = token(payload -> {});

        GoogleIdentity identity = verifier.verify(idToken);

        assertThat(identity).isEqualTo(new GoogleIdentity("sub-alice", "alice@gmail.com", true));
    }

    @Test
    void un_e_mail_sans_attestation_de_verification_est_considere_non_verifie() throws Exception {
        String idToken = token(payload -> payload.setEmailVerified(null));

        GoogleIdentity identity = verifier.verify(idToken);

        assertThat(identity.emailVerified()).isFalse();
    }

    @Test
    void refuse_un_jeton_destine_a_une_autre_application() throws Exception {
        String idToken = token(payload -> payload.setAudience("autre-application.apps.googleusercontent.com"));

        assertThatThrownBy(() -> verifier.verify(idToken)).isInstanceOf(InvalidGoogleTokenException.class);
    }

    @Test
    void refuse_un_jeton_expire() throws Exception {
        Instant hier = Instant.now().minus(Duration.ofDays(1));
        String idToken = token(payload -> payload.setIssuedAtTimeSeconds(hier.getEpochSecond())
                .setExpirationTimeSeconds(hier.plus(Duration.ofHours(1)).getEpochSecond()));

        assertThatThrownBy(() -> verifier.verify(idToken)).isInstanceOf(InvalidGoogleTokenException.class);
    }

    @Test
    void refuse_un_jeton_d_un_autre_emetteur() throws Exception {
        String idToken = token(payload -> payload.setIssuer("https://faux-google.example.com"));

        assertThatThrownBy(() -> verifier.verify(idToken)).isInstanceOf(InvalidGoogleTokenException.class);
    }

    @Test
    void refuse_un_jeton_qui_n_est_pas_signe_par_google() throws Exception {
        var generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        String idToken = token(generator.generateKeyPair().getPrivate(), payload -> {});

        assertThatThrownBy(() -> verifier.verify(idToken)).isInstanceOf(InvalidGoogleTokenException.class);
    }

    @Test
    void refuse_un_jeton_mal_forme() {
        assertThatThrownBy(() -> verifier.verify("pas-un-jeton")).isInstanceOf(InvalidGoogleTokenException.class);
        assertThatThrownBy(() -> verifier.verify("a.b.c")).isInstanceOf(InvalidGoogleTokenException.class);
    }

    @Test
    void google_injoignable_rend_la_connexion_indisponible_plutot_que_refusee() throws Exception {
        HttpTransport unreachable = new MockHttpTransport() {
            @Override
            public LowLevelHttpRequest buildRequest(String method, String url) throws IOException {
                throw new IOException("réseau coupé");
            }
        };
        var offline = new GoogleIdTokenIdentityVerifier(CLIENT_ID, unreachable);
        String idToken = token(payload -> {});

        assertThatThrownBy(() -> offline.verify(idToken)).isInstanceOf(GoogleSignInUnavailableException.class);
    }

    @Test
    void des_certificats_google_illisibles_rendent_la_connexion_indisponible() throws Exception {
        var broken = new GoogleIdTokenIdentityVerifier(CLIENT_ID, certificatesEndpoint("[]"));
        String idToken = token(payload -> {});

        assertThatThrownBy(() -> broken.verify(idToken)).isInstanceOf(GoogleSignInUnavailableException.class);
    }

    private static String token(Consumer<GoogleIdToken.Payload> customize) throws Exception {
        return token(googleKey, customize);
    }

    private static String token(PrivateKey key, Consumer<GoogleIdToken.Payload> customize) throws Exception {
        Instant now = Instant.now();
        var header = new JsonWebSignature.Header().setAlgorithm("RS256").setType("JWT").setKeyId(KEY_ID);
        var payload = new GoogleIdToken.Payload()
                .setIssuer("https://accounts.google.com")
                .setAudience(CLIENT_ID)
                .setSubject("sub-alice")
                .setIssuedAtTimeSeconds(now.getEpochSecond())
                .setExpirationTimeSeconds(now.plus(Duration.ofHours(1)).getEpochSecond());
        payload.setEmail("alice@gmail.com").setEmailVerified(true);
        customize.accept(payload);
        return JsonWebSignature.signUsingRsaSha256(key, GsonFactory.getDefaultInstance(), header, payload);
    }

    /** Ce que publie Google : {@code {"<kid>": "<certificat PEM>"}}. */
    private static String publishedCertificates(Certificate certificate) throws Exception {
        String pem = "-----BEGIN CERTIFICATE-----\n"
                + Base64.getMimeEncoder(64, "\n".getBytes()).encodeToString(certificate.getEncoded())
                + "\n-----END CERTIFICATE-----\n";
        return GsonFactory.getDefaultInstance().toString(Map.of(KEY_ID, pem));
    }

    /** Point d'accès des certificats publics de Google, avec une durée de cache (une réponse par vérifieur). */
    private static HttpTransport certificatesEndpoint(String body) {
        return new MockHttpTransport.Builder()
                .setLowLevelHttpResponse(new MockLowLevelHttpResponse()
                        .setContentType("application/json")
                        .addHeader("Cache-Control", "public, max-age=3600")
                        .setContent(body))
                .build();
    }
}
