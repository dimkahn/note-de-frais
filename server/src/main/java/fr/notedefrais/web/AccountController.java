package fr.notedefrais.web;

import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.Quota;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/account")
public class AccountController {

    private final AccountService accounts;
    private final Quota quota;

    public AccountController(AccountService accounts, Quota quota) {
        this.accounts = accounts;
        this.quota = quota;
    }

    @GetMapping
    public AccountDetailsDto get(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID accountId) {
        return AccountDetailsDto.of(accounts.get(accountId), accounts.limitsOf(accountId), quota.usedBytes(accountId));
    }
}
