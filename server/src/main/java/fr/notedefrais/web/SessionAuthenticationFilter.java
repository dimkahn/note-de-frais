package fr.notedefrais.web;

import fr.notedefrais.account.AccountService;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.util.Set;
import java.util.UUID;
import org.springframework.http.HttpHeaders;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Exige une session valide ({@code Authorization: Bearer <jeton>}) sur l'API, sauf pour l'inscription,
 * les connexions (mot de passe ou clé d'appareil) et l'administration (protégée par son propre jeton).
 * Le compte authentifié est exposé aux contrôleurs dans l'attribut de requête {@link #ACCOUNT_ID}.
 */
@Component
public class SessionAuthenticationFilter extends OncePerRequestFilter {

    public static final String ACCOUNT_ID = "fr.notedefrais.accountId";
    public static final String TOKEN = "fr.notedefrais.sessionToken";

    private static final Set<String> PUBLIC = Set.of("/api/auth/register", "/api/auth/login", "/api/auth/device-login");
    private static final String BEARER = "Bearer ";

    private final AccountService accounts;

    public SessionAuthenticationFilter(AccountService accounts) {
        this.accounts = accounts;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String uri = request.getRequestURI();
        return !uri.startsWith("/api/") || uri.startsWith("/api/admin/") || PUBLIC.contains(uri);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String token = bearerToken(req);
        UUID accountId = token == null ? null : accounts.authenticate(token).orElse(null);
        if (accountId == null) {
            res.setHeader(HttpHeaders.WWW_AUTHENTICATE, "Bearer");
            res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Session absente ou expirée");
            return;
        }
        req.setAttribute(ACCOUNT_ID, accountId);
        req.setAttribute(TOKEN, token);
        chain.doFilter(req, res);
    }

    private static String bearerToken(HttpServletRequest req) {
        String header = req.getHeader(HttpHeaders.AUTHORIZATION);
        if (header == null || !header.regionMatches(true, 0, BEARER, 0, BEARER.length())) return null;
        String token = header.substring(BEARER.length()).strip();
        return token.isEmpty() ? null : token;
    }
}
