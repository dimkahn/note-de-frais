package fr.notedefrais.extraction;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.sun.net.httpserver.HttpServer;
import fr.notedefrais.expense.Category;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;

/** Vérifie le contrat avec l'API Claude contre un serveur HTTP local (aucun appel réel). */
class ClaudeReceiptExtractorTest {

    static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, 1, 2, 3};

    HttpServer server;
    final AtomicReference<String> lastRequest = new AtomicReference<>();

    @AfterEach
    void stop() {
        if (server != null) server.stop(0);
    }

    @Test
    void envoie_l_image_et_lit_la_reponse_structuree() throws IOException {
        var extractor = extractorAnswering(200, message("end_turn", """
                {"merchant":"Le Bistrot","category":"RESTAURANT","date":"2026-03-10","amountTotal":"42.50",\
                "amountVat":"3.86","currency":"EUR","city":"Paris","country":"FR","address":"1 rue de Rivoli",\
                "paymentMethod":"CB","description":"Déjeuner"}"""));

        ReceiptExtraction result = extractor.extract(JPEG);

        assertThat(result.fields().merchant()).isEqualTo("Le Bistrot");
        assertThat(result.fields().category()).isEqualTo(Category.RESTAURANT);
        assertThat(result.fields().amountTotal()).isEqualByComparingTo("42.50");
        assertThat(result.raw()).contains("Le Bistrot");
        assertThat(lastRequest.get())
                .contains("\"model\":\"claude-opus-5-5\"")
                .contains(Base64.getEncoder().encodeToString(JPEG))
                .contains("image/jpeg");
    }

    @Test
    void un_refus_du_modele_est_une_erreur_d_extraction() throws IOException {
        var extractor = extractorAnswering(200, message("refusal", ""));

        assertThatThrownBy(() -> extractor.extract(JPEG))
                .isInstanceOf(ExtractionException.class)
                .hasMessageContaining("refus");
    }

    @Test
    void une_erreur_de_l_api_est_une_erreur_d_extraction() throws IOException {
        var extractor = extractorAnswering(500,
                "{\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"boom\"}}");

        assertThatThrownBy(() -> extractor.extract(JPEG)).isInstanceOf(ExtractionException.class);
    }

    private ClaudeReceiptExtractor extractorAnswering(int status, String body) throws IOException {
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> {
            lastRequest.set(new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8));
            byte[] bytes = body.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().add("Content-Type", "application/json");
            exchange.sendResponseHeaders(status, bytes.length);
            exchange.getResponseBody().write(bytes);
            exchange.close();
        });
        server.start();
        var client = AnthropicOkHttpClient.builder()
                .apiKey("test")
                .baseUrl("http://127.0.0.1:" + server.getAddress().getPort())
                .maxRetries(0)
                .build();
        return new ClaudeReceiptExtractor(client, "claude-opus-5-5", 4000);
    }

    private static String message(String stopReason, String text) {
        String escaped = text.replace("\\", "\\\\").replace("\"", "\\\"");
        String content = text.isEmpty() ? "[]" : "[{\"type\":\"text\",\"text\":\"" + escaped + "\"}]";
        return """
                {"id":"msg_1","type":"message","role":"assistant","model":"claude-opus-5-5",
                 "content":%s,"stop_reason":"%s","stop_sequence":null,
                 "usage":{"input_tokens":10,"output_tokens":20}}""".formatted(content, stopReason);
    }
}
