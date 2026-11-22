package fr.notedefrais.expense;

import static org.assertj.core.api.Assertions.assertThat;

import fr.notedefrais.expense.ExpenseSummary.GroupBy;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.Test;

class ExpenseSummaryTest {

    @Test
    void regroupe_par_categorie_avec_total_par_devise() {
        var expenses = List.of(
                expense(Category.RESTAURANT, "Paris", "2026-03-01", "20.00", "EUR"),
                expense(Category.RESTAURANT, "Lyon", "2026-03-15", "15.50", "EUR"),
                expense(Category.RESTAURANT, "Genève", "2026-04-02", "30.00", "CHF"),
                expense(Category.HOTEL, "Lyon", "2026-03-15", "90.00", "EUR"));

        var groups = ExpenseSummary.group(expenses, GroupBy.CATEGORY);

        assertThat(groups).hasSize(2);
        var restaurant = groups.getFirst();
        assertThat(restaurant.key()).isEqualTo("RESTAURANT");
        assertThat(restaurant.count()).isEqualTo(3);
        assertThat(restaurant.totals()).containsEntry("EUR", new BigDecimal("35.50"))
                .containsEntry("CHF", new BigDecimal("30.00"));
    }

    @Test
    void regroupe_par_mois_dans_l_ordre_chronologique() {
        var expenses = List.of(
                expense(Category.HOTEL, "Lyon", "2026-04-02", "10.00", "EUR"),
                expense(Category.HOTEL, "Lyon", "2026-03-15", "10.00", "EUR"));

        var groups = ExpenseSummary.group(expenses, GroupBy.MONTH);

        assertThat(groups).extracting(ExpenseSummary.Group::key).containsExactly("2026-03", "2026-04");
    }

    @Test
    void les_valeurs_inconnues_sont_regroupees_sous_une_cle_dediee() {
        var e = new Expense(UUID.randomUUID());

        var groups = ExpenseSummary.group(List.of(e), GroupBy.CITY);

        assertThat(groups.getFirst().key()).isEqualTo(ExpenseSummary.UNKNOWN);
        assertThat(groups.getFirst().totals()).isEmpty();
    }

    private static Expense expense(Category c, String city, String date, String amount, String currency) {
        var e = new Expense(UUID.randomUUID());
        e.setCategory(c);
        e.setCity(city);
        e.setExpenseDate(LocalDate.parse(date));
        e.setAmountTotal(new BigDecimal(amount));
        e.setCurrency(currency);
        return e;
    }
}
