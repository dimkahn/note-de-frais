package fr.notedefrais.extraction;

import fr.notedefrais.expense.Category;
import java.math.BigDecimal;
import java.time.LocalDate;

/** Informations extraites d'un justificatif, typées et normalisées. */
public record ReceiptFields(
        String merchant,
        Category category,
        LocalDate expenseDate,
        BigDecimal amountTotal,
        BigDecimal amountVat,
        String currency,
        String city,
        String country,
        String address,
        String paymentMethod,
        String description) {}
