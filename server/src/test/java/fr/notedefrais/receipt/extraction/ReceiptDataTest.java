package fr.notedefrais.receipt.extraction;

import static org.assertj.core.api.Assertions.assertThat;

import fr.notedefrais.expense.Category;
import java.math.BigDecimal;
import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class ReceiptDataTest {

    @Test
    void convertit_les_champs_textuels_en_types_metier() {
        var data = new ReceiptData("Le Bistrot", Category.RESTAURANT, "2026-03-10", "42,50", "3.86",
                "eur", "Paris", "FR", "1 rue de Rivoli", "CB", "Déjeuner client");

        var fields = data.toFields();

        assertThat(fields.amountTotal()).isEqualByComparingTo(new BigDecimal("42.50"));
        assertThat(fields.amountVat()).isEqualByComparingTo(new BigDecimal("3.86"));
        assertThat(fields.expenseDate()).isEqualTo(LocalDate.of(2026, 3, 10));
        assertThat(fields.currency()).isEqualTo("EUR");
        assertThat(fields.country()).isEqualTo("FR");
    }

    @Test
    void les_valeurs_vides_ou_illisibles_deviennent_absentes() {
        var data = new ReceiptData(" ", null, "10/03/2026 ?", "", "n/a", "", "", "", "", "", "");

        var fields = data.toFields();

        assertThat(fields.merchant()).isNull();
        assertThat(fields.category()).isEqualTo(Category.AUTRE);
        assertThat(fields.expenseDate()).isNull();
        assertThat(fields.amountTotal()).isNull();
        assertThat(fields.amountVat()).isNull();
        assertThat(fields.currency()).isNull();
    }

    @Test
    void ignore_les_separateurs_de_milliers_et_symboles() {
        var data = new ReceiptData("Hôtel", Category.HOTEL, "2026-01-05", "1 234,56 €", "", "EUR",
                "", "", "", "", "");

        assertThat(data.toFields().amountTotal()).isEqualByComparingTo(new BigDecimal("1234.56"));
    }
}
