package fr.notedefrais.account.web;

import fr.notedefrais.account.AccountService;
import fr.notedefrais.account.Plan;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotNull;
import org.springframework.web.bind.annotation.*;

/** Administration (jeton {@code X-Api-Token}, voir {@code ApiTokenFilter}). */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final AccountService service;

    public AdminController(AccountService service) {
        this.service = service;
    }

    /** Attribution manuelle d'une offre, en attendant le paiement. */
    @PutMapping("/accounts/{email}/plan")
    public AccountDto changePlan(@PathVariable String email, @Valid @RequestBody PlanChange body) {
        return AccountDto.of(service.changePlan(email, body.plan()));
    }

    public record PlanChange(@NotNull Plan plan) {}
}
