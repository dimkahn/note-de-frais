package fr.notedefrais.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * Jeton d'administration (en-tête X-Api-Token) exigé sur {@code /api/admin/**}.
 * Sans jeton configuré, l'administration est fermée. Les utilisateurs passent par leur session.
 */
@Component
@EnableConfigurationProperties(AppProperties.class)
public class ApiTokenFilter extends OncePerRequestFilter {

    private final byte[] expected;

    public ApiTokenFilter(AppProperties props) {
        String token = props.apiToken();
        this.expected = token == null || token.isBlank() ? null : token.getBytes(StandardCharsets.UTF_8);
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        return !request.getRequestURI().startsWith("/api/admin/");
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        String given = req.getHeader("X-Api-Token");
        if (expected == null || given == null
                || !MessageDigest.isEqual(expected, given.getBytes(StandardCharsets.UTF_8))) {
            res.sendError(HttpServletResponse.SC_UNAUTHORIZED, "Jeton d'administration invalide");
            return;
        }
        chain.doFilter(req, res);
    }
}
