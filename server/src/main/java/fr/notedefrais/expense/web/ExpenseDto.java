package fr.notedefrais.expense.web;

import fr.notedefrais.expense.Category;
import fr.notedefrais.expense.Expense;
import fr.notedefrais.receipt.imaging.ImageFilter;
import fr.notedefrais.expense.ProcessingStatus;
import java.math.BigDecimal;
import java.time.Instant;
import java.time.LocalDate;
import java.util.UUID;

/** Représentation JSON d'une dépense. */
public record ExpenseDto(
        UUID id,
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
        String description,
        boolean userEdited,
        ImageFilter filter,
        boolean cropped,
        String corners,
        boolean hasProcessedImage,
        ProcessingStatus status,
        String processingError,
        boolean deleted,
        Instant createdAt,
        Instant updatedAt) {

    static ExpenseDto of(Expense e) {
        return new ExpenseDto(e.getId(), e.getMerchant(), e.getCategory(), e.getExpenseDate(), e.getAmountTotal(),
                e.getAmountVat(), e.getCurrency(), e.getCity(), e.getCountry(), e.getAddress(), e.getPaymentMethod(),
                e.getDescription(), e.isUserEdited(), e.getFilter(), e.isCropped(), e.getCorners(), e.getProcessedFile() != null,
                e.getStatus(), e.getProcessingError(), e.isDeleted(), e.getCreatedAt(), e.getUpdatedAt());
    }
}
