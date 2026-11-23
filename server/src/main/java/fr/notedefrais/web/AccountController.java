package fr.notedefrais.web;

import fr.notedefrais.account.AccountService;
import fr.notedefrais.expense.ExpenseService;
import java.util.UUID;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/account")
public class AccountController {

    private final AccountService accounts;
    private final ExpenseService expenses;

    public AccountController(AccountService accounts, ExpenseService expenses) {
        this.accounts = accounts;
        this.expenses = expenses;
    }

    @GetMapping
    public AccountDetailsDto get(@RequestAttribute(SessionAuthenticationFilter.ACCOUNT_ID) UUID accountId) {
        return AccountDetailsDto.of(accounts.get(accountId), accounts.limitsOf(accountId), expenses.usedBytes(accountId));
    }
}
