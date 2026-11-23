package fr.notedefrais.account;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.util.Base64;
import java.util.HexFormat;
import java.util.Locale;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.transaction.annotation.Transactional;

/** Comptes, sessions et clés d'appareil (branché dans {@code InfrastructureConfig}). */
public class AccountService implements AccountLimits {

    private static final int TOKEN_BYTES = 32; // 256 bits
    /** BCrypt ignore (et Spring refuse) tout ce qui dépasse 72 octets. */
    private static final int MAX_PASSWORD_BYTES = 72;

    private final AccountRepository accounts;
    private final SessionRepository sessions;
    private final DeviceKeyRepository devices;
    private final PasswordEncoder passwordEncoder;
    private final Clock clock;
    private final Duration sessionTtl;
    private final Map<Plan, PlanLimits> plans;
    private final SecureRandom random = new SecureRandom();
    /** Comparé quand l'e-mail est inconnu : la réponse prend le même temps qu'un mauvais mot de passe. */
    private final String decoyHash;

    public AccountService(AccountRepository accounts, SessionRepository sessions, DeviceKeyRepository devices,
                          PasswordEncoder passwordEncoder, Clock clock, Duration sessionTtl,
                          Map<Plan, PlanLimits> plans) {
        this.accounts = accounts;
        this.sessions = sessions;
        this.devices = devices;
        this.passwordEncoder = passwordEncoder;
        this.clock = clock;
        this.sessionTtl = sessionTtl;
        for (Plan plan : Plan.values()) {
            if (!plans.containsKey(plan)) throw new IllegalArgumentException("Limites non configurées pour l'offre " + plan);
        }
        this.plans = Map.copyOf(plans);
        this.decoyHash = passwordEncoder.encode(UUID.randomUUID().toString());
    }

    @Transactional
    public Authentication register(String email, String password) {
        String normalized = normalize(email);
        if (password.getBytes(StandardCharsets.UTF_8).length > MAX_PASSWORD_BYTES) {
            throw new InvalidPasswordException("Mot de passe trop long (72 octets au plus)");
        }
        if (accounts.findByEmail(normalized).isPresent()) throw new EmailAlreadyUsedException();
        Account account = accounts.save(new Account(normalized, passwordEncoder.encode(password)));
        return new Authentication(openSession(account), account);
    }

    @Transactional
    public Authentication login(String email, String password) {
        Optional<Account> account = accounts.findByEmail(normalize(email));
        if (account.isPresent() && account.get().getPasswordHash() == null) throw new PasswordNotSetException();
        String hash = account.map(Account::getPasswordHash).orElse(decoyHash);
        if (account.isEmpty() || !passwordEncoder.matches(password, hash)) throw new InvalidCredentialsException();
        return new Authentication(openSession(account.get()), account.get());
    }

    /**
     * Connexion par une identité Google déjà vérifiée : le compte lié à cet identifiant Google ;
     * sinon le compte de même e-mail, lié au passage ; sinon un nouveau compte sans mot de passe.
     * Un e-mail que Google ne certifie pas n'ouvre ni ne lie aucun compte.
     */
    @Transactional
    public Authentication googleLogin(GoogleIdentity identity) {
        Account account = accounts.findByGoogleSubject(identity.subject())
                .orElseGet(() -> linkOrCreate(identity));
        return new Authentication(openSession(account), account);
    }

    private Account linkOrCreate(GoogleIdentity identity) {
        if (!identity.emailVerified() || identity.email() == null) {
            throw new GoogleAccountRefusedException(
                    "Adresse e-mail Google non vérifiée : connectez-vous avec votre e-mail et votre mot de passe");
        }
        String email = normalize(identity.email());
        Optional<Account> existing = accounts.findByEmail(email);
        if (existing.isEmpty()) return accounts.save(Account.fromGoogle(email, identity.subject()));
        Account account = existing.get();
        if (account.getGoogleSubject() != null) {
            throw new GoogleAccountRefusedException("Ce compte est déjà lié à un autre compte Google");
        }
        // L'inscription ne prouve pas la possession de l'e-mail : un tiers a pu créer ce compte avant
        // son titulaire. La liaison lui en retire l'accès (mot de passe, sessions, clés d'appareil).
        account.linkGoogle(identity.subject());
        sessions.deleteByAccountId(account.getId());
        devices.deleteByAccountId(account.getId());
        return accounts.save(account);
    }

    @Transactional
    public void logout(String token) {
        sessions.deleteById(hash(token));
    }

    /** Compte associé à un jeton de session valide (ni inconnu, ni expiré, ni révoqué). */
    @Transactional(readOnly = true)
    public Optional<UUID> authenticate(String token) {
        return sessions.findById(hash(token))
                .filter(s -> !s.isExpiredAt(clock.instant()))
                .map(Session::getAccountId);
    }

    @Transactional(readOnly = true)
    public Account get(UUID accountId) {
        return accounts.findById(accountId).orElseThrow(InvalidCredentialsException::new);
    }

    @Override
    @Transactional(readOnly = true)
    public PlanLimits limitsOf(UUID accountId) {
        return plans.get(get(accountId).getPlan());
    }

    /** Attribution manuelle d'une offre (administration). */
    @Transactional
    public Account changePlan(String email, Plan plan) {
        Account account = accounts.findByEmail(normalize(email)).orElseThrow(() -> new AccountNotFoundException(email));
        account.changePlan(plan);
        return accounts.save(account);
    }

    /** Émet une clé d'appareil pour la connexion par empreinte ; rendue une seule fois, jamais stockée. */
    @Transactional
    public String registerDevice(UUID accountId, String label) {
        String deviceKey = randomToken();
        devices.save(new DeviceKey(hash(deviceKey), accountId, label, clock.instant()));
        return deviceKey;
    }

    /** Ouvre une nouvelle session à partir d'une clé d'appareil valide. */
    @Transactional
    public Authentication deviceLogin(String deviceKey) {
        Account account = devices.findById(hash(deviceKey))
                .flatMap(device -> accounts.findById(device.getAccountId()))
                .orElseThrow(InvalidDeviceKeyException::new);
        return new Authentication(openSession(account), account);
    }

    /** Révoque la clé d'appareil si elle appartient au compte ; sans effet sinon. */
    @Transactional
    public void revokeDevice(UUID accountId, String deviceKey) {
        devices.findById(hash(deviceKey))
                .filter(device -> device.getAccountId().equals(accountId))
                .ifPresent(devices::delete);
    }

    private String openSession(Account account) {
        String token = randomToken();
        sessions.save(new Session(hash(token), account.getId(), clock.instant().plus(sessionTtl)));
        return token;
    }

    private String randomToken() {
        byte[] bytes = new byte[TOKEN_BYTES];
        random.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private static String normalize(String email) {
        return email.strip().toLowerCase(Locale.ROOT);
    }

    private static String hash(String token) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 indisponible", e);
        }
    }
}
