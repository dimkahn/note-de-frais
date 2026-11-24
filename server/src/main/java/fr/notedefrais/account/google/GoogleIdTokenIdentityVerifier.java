package fr.notedefrais.account.google;

import com.google.api.client.googleapis.auth.oauth2.GoogleIdToken;
import com.google.api.client.googleapis.auth.oauth2.GoogleIdTokenVerifier;
import com.google.api.client.http.HttpTransport;
import com.google.api.client.json.JsonFactory;
import com.google.api.client.json.gson.GsonFactory;
import fr.notedefrais.account.GoogleIdentity;
import fr.notedefrais.account.GoogleIdentityVerifier;
import fr.notedefrais.account.GoogleSignInUnavailableException;
import fr.notedefrais.account.InvalidGoogleTokenException;
import java.io.IOException;
import java.security.GeneralSecurityException;
import java.util.List;

/**
 * Vérification des jetons d'identité Google par la bibliothèque officielle : signature (certificats
 * publics de Google, mis en cache), émetteur, audience (l'identifiant client OAuth « web » du serveur)
 * et validité.
 */
public final class GoogleIdTokenIdentityVerifier implements GoogleIdentityVerifier {

    private final JsonFactory json = GsonFactory.getDefaultInstance();
    private final GoogleIdTokenVerifier verifier;

    public GoogleIdTokenIdentityVerifier(String clientId, HttpTransport transport) {
        this.verifier = new GoogleIdTokenVerifier.Builder(transport, json).setAudience(List.of(clientId)).build();
    }

    @Override
    public GoogleIdentity verify(String idToken) {
        GoogleIdToken.Payload payload = verified(parse(idToken)).getPayload();
        return new GoogleIdentity(payload.getSubject(), payload.getEmail(),
                Boolean.TRUE.equals(payload.getEmailVerified()));
    }

    private GoogleIdToken parse(String idToken) {
        try {
            return GoogleIdToken.parse(json, idToken);
        } catch (IOException | IllegalArgumentException e) {
            throw new InvalidGoogleTokenException();
        }
    }

    private GoogleIdToken verified(GoogleIdToken token) {
        try {
            if (verifier.verify(token)) return token;
        } catch (IOException e) {
            throw new GoogleSignInUnavailableException("Google est injoignable : réessayez plus tard", e);
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new GoogleSignInUnavailableException("Certificats de Google illisibles : réessayez plus tard", e);
        }
        throw new InvalidGoogleTokenException();
    }
}
