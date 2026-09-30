/**
 * Grounded FAQ answers from LoanSeva_FAQ__mdt. Matching is keyword-based (any language);
 * answers are merged with values from LoanSeva_Config__mdt so rates/timelines are never hard-coded.
 */
public with sharing class LoanSevaFaqMatcher {
    private static List<LoanSeva_FAQ__mdt> faqs;

    public static List<LoanSeva_FAQ__mdt> all() {
        if (faqs == null) {
            faqs = [
                SELECT DeveloperName, Question__c, Keywords__c, Sort_Order__c, English__c, Hindi__c, Marathi__c
                FROM LoanSeva_FAQ__mdt
                ORDER BY Sort_Order__c ASC
            ];
        }
        return faqs;
    }

    /** FAQs sorted at or above this are general fallbacks, used only when no specific FAQ matches. */
    public static final Integer FALLBACK_ORDER = 900;

    /** Highest keyword-hit specific FAQ; ties go to the lower sort order. Null when nothing matches. */
    public static LoanSeva_FAQ__mdt bestMatch(String question) {
        return bestMatch(question, false);
    }

    /** As bestMatch; with includeGeneral, falls back to the general FAQs (for text known to be a question). */
    public static LoanSeva_FAQ__mdt bestMatch(String question, Boolean includeGeneral) {
        if (String.isBlank(question)) {
            return null;
        }
        String q = ' ' + question.toLowerCase().replaceAll('[?!.,]', ' ') + ' ';
        LoanSeva_FAQ__mdt best = bestOf(q, false);
        return best == null && includeGeneral ? bestOf(q, true) : best;
    }

    private static LoanSeva_FAQ__mdt bestOf(String q, Boolean fallback) {
        LoanSeva_FAQ__mdt best;
        Integer bestScore = 0;
        for (LoanSeva_FAQ__mdt f : all()) {
            if ((f.Sort_Order__c != null && f.Sort_Order__c >= FALLBACK_ORDER) != fallback) {
                continue;
            }
            Integer score = 0;
            for (String k : String.valueOf(f.Keywords__c).split(',')) {
                String kw = k.trim().toLowerCase();
                // word-start match so "use" does not hit "because"
                if (String.isNotBlank(kw) && q.contains(' ' + kw)) {
                    // longer phrases are stronger signals
                    score += kw.contains(' ') ? 2 : 1;
                }
            }
            if (score > bestScore) {
                best = f;
                bestScore = score;
            }
        }
        return best;
    }

    public static String render(LoanSeva_FAQ__mdt f, String lang) {
        return LoanSevaI18n.mergeTokens(LoanSevaI18n.pick(f.English__c, f.Hindi__c, f.Marathi__c, lang), configTokens());
    }

    public static Map<String, Object> configTokens() {
        LoanSeva_Config__mdt c = LoanSevaConfig.get();
        List<Integer> tenures = LoanSevaConfig.tenureOptions();
        return new Map<String, Object>{
            'rate' => c.Rate_Display__c,
            'baseRate' => c.Base_Rate__c,
            'disbursal' => c.Disbursal_Timeline__c,
            'feePct' => c.Processing_Fee_Pct__c,
            'minTenure' => tenures[0],
            'maxTenure' => tenures[tenures.size() - 1],
            'minAmount' => LoanSevaI18n.inr(c.Min_Topup_Amount__c)
        };
    }
}
