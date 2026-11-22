package fr.notedefrais.expense;

import static org.assertj.core.api.Assertions.assertThat;

import fr.notedefrais.expense.ExpenseSpecs.Criteria;
import java.time.LocalDate;
import java.util.List;
import java.util.UUID;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest;

@DataJpaTest
class ExpenseSpecsTest {

    @Autowired
    ExpenseRepository repository;

    @BeforeEach
    void setUp() {
        repository.saveAll(List.of(
                expense("Le Bistrot", Category.RESTAURANT, "Paris", LocalDate.of(2026, 3, 10), false),
                expense("Ibis Lyon", Category.HOTEL, "Lyon", LocalDate.of(2026, 3, 11), false),
                expense("Total Énergies", Category.CARBURANT, "Lyon", LocalDate.of(2026, 4, 2), false),
                expense("Ancien resto", Category.RESTAURANT, "Paris", LocalDate.of(2026, 3, 12), true)));
    }

    @Test
    void filtre_par_categorie_en_ignorant_les_supprimees() {
        var result = search(new Criteria(Category.RESTAURANT, null, null, null, null, null, null));

        assertThat(result).extracting(Expense::getMerchant).containsExactly("Le Bistrot");
    }

    @Test
    void filtre_par_ville_sans_tenir_compte_de_la_casse() {
        var result = search(new Criteria(null, "LYON", null, null, null, null, null));

        assertThat(result).extracting(Expense::getMerchant).containsExactlyInAnyOrder("Ibis Lyon", "Total Énergies");
    }

    @Test
    void filtre_par_periode_bornes_incluses() {
        var result = search(new Criteria(null, null, null, null,
                LocalDate.of(2026, 3, 11), LocalDate.of(2026, 4, 2), null));

        assertThat(result).extracting(Expense::getMerchant).containsExactlyInAnyOrder("Ibis Lyon", "Total Énergies");
    }

    @Test
    void recherche_libre_sur_le_commercant() {
        var result = search(new Criteria(null, null, null, null, null, null, "bistrot"));

        assertThat(result).extracting(Expense::getMerchant).containsExactly("Le Bistrot");
    }

    @Test
    void criteres_combines() {
        var result = search(new Criteria(Category.HOTEL, "lyon", null, null, null, null, null));

        assertThat(result).extracting(Expense::getMerchant).containsExactly("Ibis Lyon");
    }

    private List<Expense> search(Criteria criteria) {
        return repository.findAll(ExpenseSpecs.matching(criteria));
    }

    private static Expense expense(String merchant, Category category, String city, LocalDate date, boolean deleted) {
        var e = new Expense(UUID.randomUUID());
        e.setMerchant(merchant);
        e.setCategory(category);
        e.setCity(city);
        e.setExpenseDate(date);
        e.setDeleted(deleted);
        return e;
    }
}
