package fr.notedefrais.extraction;

import com.anthropic.client.AnthropicClient;
import com.anthropic.errors.AnthropicException;
import com.anthropic.models.beta.messages.BetaBase64ImageSource;
import com.anthropic.models.beta.messages.BetaContentBlockParam;
import com.anthropic.models.beta.messages.BetaStopReason;
import com.anthropic.models.beta.messages.MessageCreateParams;
import com.anthropic.models.beta.messages.StructuredContentBlock;
import com.anthropic.models.beta.messages.StructuredMessage;
import com.anthropic.models.beta.messages.StructuredMessageCreateParams;
import com.anthropic.models.beta.messages.StructuredTextBlock;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.util.Base64;
import java.util.List;

/**
 * Extraction des informations d'un justificatif par Claude (vision + sortie structurée).
 *
 * <p>Seule classe du projet qui dépend du SDK Anthropic. Les refus du modèle sont rejoués
 * automatiquement sur un modèle de repli côté serveur ({@code fallbacks: "default"}).
 */
public final class ClaudeReceiptExtractor implements ReceiptExtractor {

    static final String FALLBACK_BETA = "server-side-fallback-2026-07-01";

    private static final String SYSTEM_PROMPT = """
            Tu extrais les informations d'un justificatif de dépense professionnelle (ticket de caisse,
            facture, note d'hôtel, billet de transport, reçu de péage ou de parking) à partir de sa photo.

            Règles :
            - Recopie les valeurs telles qu'imprimées ; ne devine pas. Si une information est absente ou
              illisible, renvoie une chaîne vide pour ce champ.
            - amountTotal est le montant total effectivement payé (TTC, pourboire compris s'il est imprimé),
              avec un point comme séparateur décimal et sans symbole.
            - amountVat est le total de TVA s'il figure sur le document, sinon vide.
            - date est la date de la transaction au format AAAA-MM-JJ (les tickets français sont en JJ/MM/AA).
            - currency : code ISO 4217 déduit du symbole ou du pays (€ → EUR).
            - city / country / address : ceux de l'établissement, pas du client.
            - category : choisis la catégorie la plus spécifique ; AUTRE seulement si aucune ne convient.
            - description : quelques mots en français résumant l'achat (ex. « Déjeuner 2 couverts »).
            """;

    private final AnthropicClient client;
    private final String model;
    private final long maxTokens;
    private final ObjectMapper json = new ObjectMapper();

    public ClaudeReceiptExtractor(AnthropicClient client, String model, long maxTokens) {
        this.client = client;
        this.model = model;
        this.maxTokens = maxTokens;
    }

    @Override
    public ReceiptExtraction extract(byte[] jpeg) {
        StructuredMessage<ReceiptData> response;
        try {
            response = client.beta().messages().create(request(jpeg));
        } catch (AnthropicException e) {
            throw new ExtractionException("Appel à Claude impossible : " + e.getMessage(), e);
        }

        if (response.stopReason().filter(BetaStopReason.REFUSAL::equals).isPresent()) {
            throw new ExtractionException("Claude a refusé de traiter ce document");
        }
        if (response.stopReason().filter(BetaStopReason.MAX_TOKENS::equals).isPresent()) {
            throw new ExtractionException("Réponse de Claude tronquée (max_tokens atteint)");
        }

        ReceiptData data = response.content().stream()
                .flatMap(block -> block.text().stream())
                .map(StructuredTextBlock::text)
                .findFirst()
                .orElseThrow(() -> new ExtractionException("Réponse de Claude sans contenu exploitable"));
        return new ReceiptExtraction(data.toFields(), toJson(data));
    }

    private StructuredMessageCreateParams<ReceiptData> request(byte[] jpeg) {
        var image = BetaContentBlockParam.ofImage(BetaBase64ImageSource.builder()
                .data(Base64.getEncoder().encodeToString(jpeg))
                .mediaType(BetaBase64ImageSource.MediaType.IMAGE_JPEG)
                .build());
        var instruction = BetaContentBlockParam.ofText("Extrais les informations de ce justificatif.");

        return MessageCreateParams.builder()
                .model(model)
                .maxTokens(maxTokens)
                .addBeta(FALLBACK_BETA)
                .fallbacksDefault()
                .system(SYSTEM_PROMPT)
                .addUserMessageOfContentBlockParams(List.of(image, instruction))
                .outputConfig(ReceiptData.class)
                .build();
    }

    private String toJson(ReceiptData data) {
        try {
            return json.writeValueAsString(data);
        } catch (JsonProcessingException e) {
            return String.valueOf(data);
        }
    }
}
