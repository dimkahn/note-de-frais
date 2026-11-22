package fr.notedefrais.config;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import fr.notedefrais.extraction.ClaudeReceiptExtractor;
import fr.notedefrais.extraction.DisabledReceiptExtractor;
import fr.notedefrais.extraction.ReceiptExtractor;
import fr.notedefrais.imaging.ImageProcessor;
import fr.notedefrais.imaging.OpenCvImageProcessor;
import fr.notedefrais.storage.FileStorage;
import fr.notedefrais.storage.LocalFileStorage;
import java.nio.file.Path;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/** Branchement des implémentations concrètes derrière les interfaces métier. */
@Configuration
public class InfrastructureConfig {

    @Bean
    FileStorage fileStorage(AppProperties props) {
        return new LocalFileStorage(Path.of(props.storageDir()));
    }

    @Bean
    ImageProcessor imageProcessor() {
        return new OpenCvImageProcessor();
    }

    /**
     * Identifiants lus dans l'environnement : ANTHROPIC_API_KEY, ou à défaut le profil
     * créé par {@code ant auth login}.
     */
    @Bean(destroyMethod = "close")
    @ConditionalOnProperty(prefix = "app.claude", name = "enabled", havingValue = "true")
    AnthropicClient anthropicClient() {
        return AnthropicOkHttpClient.fromEnv();
    }

    @Bean
    @ConditionalOnProperty(prefix = "app.claude", name = "enabled", havingValue = "true")
    ReceiptExtractor claudeReceiptExtractor(AnthropicClient client, AppProperties props) {
        return new ClaudeReceiptExtractor(client, props.claude().model(), props.claude().maxTokens());
    }

    @Bean
    @ConditionalOnProperty(prefix = "app.claude", name = "enabled", havingValue = "false", matchIfMissing = true)
    ReceiptExtractor disabledReceiptExtractor() {
        return new DisabledReceiptExtractor();
    }
}
