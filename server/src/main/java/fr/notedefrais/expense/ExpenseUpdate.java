package fr.notedefrais.expense;

import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import java.math.BigDecimal;
import java.time.LocalDate;

/** Valeurs des champs d'une dépense (saisie manuelle ou extraction). */
public record ExpenseUpdate(
        @Size(max = 255) String merchant,
        Category category,
        LocalDate expenseDate,
        @Digits(integer = 10, fraction = 2) BigDecimal amountTotal,
        @Digits(integer = 10, fraction = 2) BigDecimal amountVat,
        @Pattern(regexp = "[A-Z]{3}") String currency,
        @Size(max = 255) String city,
        @Size(max = 255) String country,
        @Size(max = 255) String address,
        @Size(max = 255) String paymentMethod,
        @Size(max = 2000) String description) {}
