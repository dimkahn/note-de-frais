package fr.notedefrais.config;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

/** Le jeton partagé X-Api-Token est désormais le jeton d'administration. */
class ApiTokenFilterTest {

    @Test
    void rejette_une_requete_d_administration_sans_le_bon_jeton() throws Exception {
        var filter = filterWithToken("secret");
        var res = new MockHttpServletResponse();

        filter.doFilter(request("/api/admin/accounts", "mauvais"), res, new MockFilterChain());

        assertThat(res.getStatus()).isEqualTo(401);
    }

    @Test
    void accepte_le_bon_jeton_d_administration() throws Exception {
        var filter = filterWithToken("secret");
        var res = new MockHttpServletResponse();
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/admin/accounts", "secret"), res, chain);

        assertThat(res.getStatus()).isEqualTo(200);
        assertThat(chain.getRequest()).isNotNull();
    }

    @Test
    void ne_s_applique_pas_aux_requetes_des_utilisateurs() throws Exception {
        var filter = filterWithToken("secret");
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/expenses", null), new MockHttpServletResponse(), chain);

        assertThat(chain.getRequest()).isNotNull();
    }

    @Test
    void sans_jeton_configure_l_administration_est_fermee() throws Exception {
        var filter = filterWithToken("");
        var res = new MockHttpServletResponse();
        var chain = new MockFilterChain();

        filter.doFilter(request("/api/admin/accounts", ""), res, chain);

        assertThat(res.getStatus()).isEqualTo(401);
        assertThat(chain.getRequest()).isNull();
    }

    private static ApiTokenFilter filterWithToken(String token) {
        return new ApiTokenFilter(new AppProperties("storage", token, null, null));
    }

    private static MockHttpServletRequest request(String uri, String token) {
        var req = new MockHttpServletRequest("GET", uri);
        if (token != null) req.addHeader("X-Api-Token", token);
        return req;
    }
}
