package fr.notedefrais.web;

import fr.notedefrais.account.AccountService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final AccountService service;

    public AuthController(AccountService service) {
        this.service = service;
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

    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestAttribute(SessionAuthenticationFilter.TOKEN) String token) {
        service.logout(token);
        return ResponseEntity.noContent().build();
    }
}
