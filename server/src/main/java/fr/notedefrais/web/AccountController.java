package fr.notedefrais.web;

import fr.notedefrais.account.AccountService;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/account")
public class AccountController {

    private final AccountService service;

    public AccountController(AccountService service) {
        this.service = service;
    }

    @GetMapping
    public AccountDto get(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID accountId) {
        return AccountDto.of(service.get(accountId));
    }
}
