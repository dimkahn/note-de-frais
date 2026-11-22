package fr.notedefrais.expense;

import java.math.BigDecimal;
import java.time.format.DateTimeFormatter;
import java.util.Collection;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.function.Function;
import java.util.stream.Collectors;

/** Regroupement des dépenses par critère, avec un total par devise (pas de conversion implicite). */
public final class ExpenseSummary {

    public static final String UNKNOWN = "(inconnu)";
    private static final DateTimeFormatter MONTH = DateTimeFormatter.ofPattern("yyyy-MM");

    public enum GroupBy {
        CATEGORY(e -> e.getCategory() == null ? null : e.getCategory().name()),
        CITY(Expense::getCity),
        COUNTRY(Expense::getCountry),
        MERCHANT(Expense::getMerchant),
        MONTH(e -> e.getExpenseDate() == null ? null : e.getExpenseDate().format(ExpenseSummary.MONTH)),
        PAYMENT_METHOD(Expense::getPaymentMethod);

        private final Function<Expense, String> key;

        GroupBy(Function<Expense, String> key) {
            this.key = key;
        }

        String keyOf(Expense e) {
            String k = key.apply(e);
            return k == null || k.isBlank() ? UNKNOWN : k;
        }
    }

    public record Group(String key, long count, Map<String, BigDecimal> totals) {}

    private ExpenseSummary() {}

    public static List<Group> group(Collection<Expense> expenses, GroupBy by) {
        Comparator<Group> order = by == GroupBy.MONTH
                ? Comparator.comparing(Group::key)
                : Comparator.comparingLong(Group::count).reversed().thenComparing(Group::key);
        return expenses.stream()
                .collect(Collectors.groupingBy(by::keyOf))
                .entrySet().stream()
                .map(entry -> new Group(entry.getKey(), entry.getValue().size(), totalsByCurrency(entry.getValue())))
                .sorted(order)
                .toList();
    }

    private static Map<String, BigDecimal> totalsByCurrency(List<Expense> expenses) {
        return expenses.stream()
                .filter(e -> e.getAmountTotal() != null)
                .collect(Collectors.groupingBy(
                        e -> e.getCurrency() == null ? UNKNOWN : e.getCurrency(),
                        TreeMap::new,
                        Collectors.reducing(BigDecimal.ZERO, Expense::getAmountTotal, BigDecimal::add)));
    }
}
