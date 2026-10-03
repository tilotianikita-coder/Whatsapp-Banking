/**
 * Structured mock provider report stored on Underwriting_Check__c.Report_Data__c as JSON and rendered by the
 * loanSevaCreditReview component: key facts (optionally toned good / warn / bad), tables and flags.
 */
public with sharing class LoanSevaReport {
    public static final String GOOD = 'good';
    public static final String WARN = 'warn';
    public static final String BAD = 'bad';

    private final List<Map<String, Object>> facts = new List<Map<String, Object>>();
    private final List<Map<String, Object>> tables = new List<Map<String, Object>>();
    private final List<Map<String, Object>> flags = new List<Map<String, Object>>();

    public LoanSevaReport fact(String label, Object value) {
        return fact(label, value, null);
    }

    public LoanSevaReport fact(String label, Object value, String tone) {
        facts.add(new Map<String, Object>{ 'label' => label, 'value' => value == null ? '—' : String.valueOf(value), 'tone' => tone });
        return this;
    }

    public LoanSevaReport table(String title, List<String> columns, List<List<String>> rows) {
        tables.add(new Map<String, Object>{ 'title' => title, 'columns' => columns, 'rows' => rows });
        return this;
    }

    public LoanSevaReport flag(String tone, String text) {
        flags.add(new Map<String, Object>{ 'tone' => tone, 'text' => text });
        return this;
    }

    public String json() {
        return JSON.serialize(new Map<String, Object>{ 'facts' => facts, 'tables' => tables, 'flags' => flags });
    }

    /** Deterministic pseudo-random numbers, seeded from the PAN so a re-run shows the same report. */
    public class Rng {
        private Long state;

        public Rng(String seed) {
            state = Math.abs((seed == null ? '' : seed).hashCode()) + 7L;
        }

        /** 0 .. n-1 */
        public Integer next(Integer n) {
            state = Math.mod(state * 1103515245L + 12345L, 2147483648L);
            return Math.mod(state / 65536L, (Long) n).intValue();
        }

        /** low .. high inclusive */
        public Integer between(Integer low, Integer high) {
            return low + next(high - low + 1);
        }

        public String pick(List<String> values) {
            return values[next(values.size())];
        }
    }

    public static String formatDate(Date d, String pattern) {
        return d == null ? '—' : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format(pattern);
    }

    public static Decimal roundTo(Decimal value, Integer step) {
        return value == null ? 0 : (value / step).setScale(0, RoundingMode.HALF_UP) * step;
    }
}
