package fr.notedefrais.account.google;

import fr.notedefrais.account.GoogleIdentity;
import fr.notedefrais.account.GoogleIdentityVerifier;
import fr.notedefrais.account.GoogleSignInUnavailableException;

/** Utilisé sans identifiant client OAuth configuré ({@code NDF_GOOGLE_CLIENT_ID}) : la connexion Google est fermée. */
public final class DisabledGoogleIdentityVerifier implements GoogleIdentityVerifier {

    @Override
    public GoogleIdentity verify(String idToken) {
        throw new GoogleSignInUnavailableException("Connexion Google non configurée sur ce serveur");
    }
}
