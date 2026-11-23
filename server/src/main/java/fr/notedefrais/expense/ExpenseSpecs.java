package fr.notedefrais.expense;

import java.time.LocalDate;
import java.util.UUID;
import org.springframework.data.jpa.domain.Specification;

/** Critères de recherche combinables. */
public final class ExpenseSpecs {

    private ExpenseSpecs() {}

    public record Criteria(Category category, String city, String country, String merchant,
                           LocalDate from, LocalDate to, String q) {}

    public static Specification<Expense> ownedBy(UUID ownerId) {
        return (root, query, cb) -> cb.equal(root.get("ownerId"), ownerId);
    }

    public static Specification<Expense> matching(Criteria c) {
        return (root, query, cb) -> {
            var p = cb.isFalse(root.get("deleted"));
            if (c.category() != null) p = cb.and(p, cb.equal(root.get("category"), c.category()));
            if (notBlank(c.city())) p = cb.and(p, cb.equal(cb.lower(root.get("city")), c.city().toLowerCase()));
            if (notBlank(c.country())) p = cb.and(p, cb.equal(cb.lower(root.get("country")), c.country().toLowerCase()));
            if (notBlank(c.merchant())) p = cb.and(p, cb.like(cb.lower(root.get("merchant")), like(c.merchant())));
            if (c.from() != null) p = cb.and(p, cb.greaterThanOrEqualTo(root.get("expenseDate"), c.from()));
            if (c.to() != null) p = cb.and(p, cb.lessThanOrEqualTo(root.get("expenseDate"), c.to()));
            if (notBlank(c.q())) {
                String q = like(c.q());
                p = cb.and(p, cb.or(
                        cb.like(cb.lower(root.get("merchant")), q),
                        cb.like(cb.lower(root.get("description")), q),
                        cb.like(cb.lower(root.get("city")), q),
                        cb.like(cb.lower(root.get("address")), q)));
            }
            return p;
        };
    }

    private static boolean notBlank(String s) {
        return s != null && !s.isBlank();
    }

    private static String like(String s) {
        return "%" + s.toLowerCase().replace("%", "\\%").replace("_", "\\_") + "%";
    }
}
