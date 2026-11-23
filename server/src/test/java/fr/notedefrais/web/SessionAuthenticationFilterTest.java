package fr.notedefrais.web;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.BDDMockito.given;
import static org.mockito.Mockito.mock;

import fr.notedefrais.account.AccountService;
import java.util.Optional;
import java.util.UUID;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class SessionAuthenticationFilterTest {

    final AccountService accounts = mock(AccountService.class);
    final SessionAuthenticationFilter filter = new SessionAuthenticationFilter(accounts);

    @Test
    void refuse_une_requete_api_sans_jeton() throws Exception {
        var res = new MockHttpServletResponse();
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/expenses", null), res, chain);

        assertThat(res.getStatus()).isEqualTo(401);
        assertThat(chain.getRequest()).isNull();
    }

    @Test
    void refuse_un_jeton_inconnu_ou_expire() throws Exception {
        given(accounts.authenticate("perime")).willReturn(Optional.empty());
        var res = new MockHttpServletResponse();

        filter.doFilter(request("/api/expenses", "Bearer perime"), res, new MockFilterChain());

        assertThat(res.getStatus()).isEqualTo(401);
    }

    @Test
    void refuse_un_autre_schema_que_bearer() throws Exception {
        var res = new MockHttpServletResponse();

        filter.doFilter(request("/api/expenses", "Basic YWxpY2U6c2VjcmV0"), res, new MockFilterChain());

        assertThat(res.getStatus()).isEqualTo(401);
    }

    @Test
    void un_jeton_valide_laisse_passer_et_expose_le_compte_a_la_requete() throws Exception {
        var accountId = UUID.randomUUID();
        given(accounts.authenticate("jeton")).willReturn(Optional.of(accountId));
        var req = request("/api/expenses", "Bearer jeton");
        var chain = new MockFilterChain();

        filter.doFilter(req, new MockHttpServletResponse(), chain);

        assertThat(chain.getRequest()).isNotNull();
        assertThat(req.getAttribute(SessionAuthenticationFilter.ACCOUNT_ID)).isEqualTo(accountId);
        assertThat(req.getAttribute(SessionAuthenticationFilter.TOKEN)).isEqualTo("jeton");
    }

    @Test
    void l_inscription_et_la_connexion_restent_accessibles_sans_jeton() throws Exception {
        for (String uri : new String[]{"/api/auth/register", "/api/auth/login"}) {
            var chain = new MockFilterChain();

            filter.doFilter(request(uri, null), new MockHttpServletResponse(), chain);

            assertThat(chain.getRequest()).as(uri).isNotNull();
        }
    }

    @Test
    void l_administration_n_utilise_pas_les_sessions() throws Exception {
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/admin/accounts", null), new MockHttpServletResponse(), chain);

        assertThat(chain.getRequest()).isNotNull();
    }

    @Test
    void la_deconnexion_exige_une_session() throws Exception {
        var res = new MockHttpServletResponse();

        filter.doFilter(request("/api/auth/logout", null), res, new MockFilterChain());

        assertThat(res.getStatus()).isEqualTo(401);
    }

    private static MockHttpServletRequest request(String uri, String authorization) {
        var req = new MockHttpServletRequest("GET", uri);
        req.setRequestURI(uri);
        if (authorization != null) req.addHeader("Authorization", authorization);
        return req;
    }
}
