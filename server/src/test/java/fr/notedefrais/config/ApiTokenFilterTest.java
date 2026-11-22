package fr.notedefrais.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

class ApiTokenFilterTest {

    @Test
    void rejette_une_requete_api_sans_le_bon_jeton() throws Exception {
        var filter = filterWithToken("secret");
        var res = new MockHttpServletResponse();

        filter.doFilter(request("/api/expenses", "mauvais"), res, new MockFilterChain());

        assertThat(res.getStatus()).isEqualTo(401);
    }

    @Test
    void accepte_le_bon_jeton() throws Exception {
        var filter = filterWithToken("secret");
        var res = new MockHttpServletResponse();
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/expenses", "secret"), res, chain);

        assertThat(res.getStatus()).isEqualTo(200);
        assertThat(chain.getRequest()).isNotNull();
    }

    @Test
    void sans_jeton_configure_tout_passe() throws Exception {
        var filter = filterWithToken("");
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/expenses", null), new MockHttpServletResponse(), chain);

        assertThat(chain.getRequest()).isNotNull();
    }

    private static ApiTokenFilter filterWithToken(String token) {
        return new ApiTokenFilter(new AppProperties("storage", token, null));
    }

    private static MockHttpServletRequest request(String uri, String token) {
        var req = new MockHttpServletRequest("GET", uri);
        if (token != null) req.addHeader("X-Api-Token", token);
        return req;
    }
}
