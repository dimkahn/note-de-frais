package fr.notedefrais.account.web;

import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.GoogleIdentityVerifier;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AccountService service;
    private final GoogleIdentityVerifier google;

    public AuthController(AccountService service, GoogleIdentityVerifier google) {
        this.service = service;
        this.google = google;
    }

    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody Credentials.Registration body) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(AuthResponse.of(service.register(body.email(), body.password())));
    }

    @PostMapping("/login")
    public AuthResponse login(@Valid @RequestBody Credentials.Login body) {
        return AuthResponse.of(service.login(body.email(), body.password()));
    }

    /** Vérification du jeton auprès de Google hors transaction, puis connexion (ou liaison, ou création). */
    @PostMapping("/google")
    public AuthResponse google(@Valid @RequestBody Credentials.Google body) {
        return AuthResponse.of(service.googleLogin(google.verify(body.idToken())));
    }

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestAttribute(SessionAuthenticationFilter.TOKEN) String token) {
        service.logout(token);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/devices")
    public ResponseEntity<DeviceKeys.Key> registerDevice(
            @RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID accountId,
            @Valid @RequestBody DeviceKeys.Registration body) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(new DeviceKeys.Key(service.registerDevice(accountId, body.label())));
    }

    @PostMapping("/device-login")
    public AuthResponse deviceLogin(@Valid @RequestBody DeviceKeys.Key body) {
        return AuthResponse.of(service.deviceLogin(body.deviceKey()));
    }

    @DeleteMapping("/devices/current")
    public ResponseEntity<Void> revokeDevice(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID accountId,
                                             @Valid @RequestBody DeviceKeys.Key body) {
        service.revokeDevice(accountId, body.deviceKey());
        return ResponseEntity.noContent().build();
    }
}
