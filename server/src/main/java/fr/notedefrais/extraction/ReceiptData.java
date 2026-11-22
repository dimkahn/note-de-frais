package fr.notedefrais.extraction;

import com.fasterxml.jackson.annotation.JsonPropertyDescription;
import fr.notedefrais.expense.Category;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.format.DateTimeParseException;
import java.util.Locale;

/**
 * Format de sortie structurée demandé à Claude. Les champs sont textuels (chaîne vide si
 * inconnue) puis convertis en types métier par {@link #toFields()}.
 */
public record ReceiptData(
        @JsonPropertyDescription("Nom du commerçant / de l'établissement") String merchant,
        @JsonPropertyDescription("Type de dépense") Category category,
        @JsonPropertyDescription("Date de la dépense au format ISO AAAA-MM-JJ") String date,
        @JsonPropertyDescription("Montant total TTC payé, chiffres uniquement, ex. 42.50") String amountTotal,
        @JsonPropertyDescription("Montant total de TVA, ex. 3.86") String amountVat,
        @JsonPropertyDescription("Code devise ISO 4217, ex. EUR") String currency,
        @JsonPropertyDescription("Ville de l'établissement") String city,
        @JsonPropertyDescription("Code pays ISO 3166-1 alpha-2, ex. FR") String country,
        @JsonPropertyDescription("Adresse de l'établissement") String address,
        @JsonPropertyDescription("Moyen de paiement : CB, espèces, chèque, virement…") String paymentMethod,
        @JsonPropertyDescription("Résumé court de ce qui a été acheté") String description) {

    public ReceiptFields toFields() {
        return new ReceiptFields(
                text(merchant),
                category == null ? Category.AUTRE : category,
                date(date),
                amount(amountTotal),
                amount(amountVat),
                upper(currency),
                text(city),
                upper(country),
                text(address),
                text(paymentMethod),
                text(description));
    }

    private static String text(String s) {
        return s == null || s.isBlank() ? null : s.strip();
    }

    private static String upper(String s) {
        String t = text(s);
        return t == null ? null : t.toUpperCase(Locale.ROOT);
    }

    private static LocalDate date(String s) {
        String t = text(s);
        if (t == null) return null;
        try {
            return LocalDate.parse(t);
        } catch (DateTimeParseException e) {
            return null;
        }
    }

    static BigDecimal amount(String s) {
        String t = text(s);
        if (t == null) return null;
        String digits = t.replaceAll("[^0-9,.\\-]", "");
        int lastSep = Math.max(digits.lastIndexOf(','), digits.lastIndexOf('.'));
        String normalized = lastSep < 0
                ? digits
                : digits.substring(0, lastSep).replaceAll("[,.]", "") + "." + digits.substring(lastSep + 1);
        try {
            return normalized.isEmpty() ? null : new BigDecimal(normalized);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
