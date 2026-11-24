package fr.notedefrais.config;

import com.anthropic.client.AnthropicClient;
import com.anthropic.client.okhttp.AnthropicOkHttpClient;
import com.google.api.client.http.javanet.NetHttpTransport;
import fr.notedefrais.account.AccountRepository;
import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.DeviceKeyRepository;
import fr.notedefrais.account.GoogleIdentityVerifier;
import fr.notedefrais.account.Quota;
import fr.notedefrais.account.StorageUsage;
import fr.notedefrais.account.SessionRepository;
import fr.notedefrais.document.DocumentPageRepository;
import fr.notedefrais.document.DocumentRepository;
import fr.notedefrais.document.DocumentService;
import fr.notedefrais.receipt.extraction.ClaudeReceiptExtractor;
import fr.notedefrais.account.google.DisabledGoogleIdentityVerifier;
import fr.notedefrais.account.google.GoogleIdTokenIdentityVerifier;
import fr.notedefrais.receipt.extraction.DisabledReceiptExtractor;
import fr.notedefrais.receipt.extraction.ReceiptExtractor;
import fr.notedefrais.receipt.imaging.ImageProcessor;
import fr.notedefrais.receipt.imaging.OpenCvImageProcessor;
import fr.notedefrais.storage.FileStorage;
import fr.notedefrais.storage.LocalFileStorage;
import java.nio.file.Path;
import java.time.Clock;
import java.util.List;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;

/** Branchement des implémentations concrètes derrière les interfaces métier. */
@Configuration
public class InfrastructureConfig {

    @Bean
    FileStorage fileStorage(AppProperties props) {
        return new LocalFileStorage(Path.of(props.storageDir()));
    }

    /** Pages dans {@code <storage-dir>/documents/<pageId>/} : un identifiant de page ne vise jamais une dépense. */
    @Bean
    DocumentService documentService(DocumentRepository documents, DocumentPageRepository pages, Quota quota,
                                    AppProperties props) {
        return new DocumentService(documents, pages, new LocalFileStorage(Path.of(props.storageDir(), "documents")), quota);
    }

    @Bean
    AccountService accountService(AccountRepository accounts, SessionRepository sessions, DeviceKeyRepository devices,
                                  AppProperties props) {
        return new AccountService(accounts, sessions, devices, new BCryptPasswordEncoder(), Clock.systemUTC(),
                props.sessionTtl(), props.planLimits());
    }

    /** Toutes les données stockées en ligne (dépenses, documents) comptent dans l'espace de l'offre. */
    @Bean
    Quota quota(List<StorageUsage> usages, AccountService accounts) {
        return new Quota(usages, accounts);
    }

    @Bean
    GoogleIdentityVerifier googleIdentityVerifier(AppProperties props) {
        AppProperties.Google google = props.google();
        return google != null && google.enabled()
                ? new GoogleIdTokenIdentityVerifier(google.clientId().strip(), new NetHttpTransport())
                : new DisabledGoogleIdentityVerifier();
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
