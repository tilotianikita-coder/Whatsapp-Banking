/**
 * Typed access to LoanSeva_Config__mdt.Default.
 * All commercial values (rates, fees, timelines) are illustrative demo placeholders.
 */
public with sharing class LoanSevaConfig {
    public static final String DEFAULT_RECORD = 'Default';

    @TestVisible
    private static LoanSeva_Config__mdt cached;

    public static LoanSeva_Config__mdt get() {
        if (cached == null) {
            cached = LoanSeva_Config__mdt.getInstance(DEFAULT_RECORD);
            if (cached == null) {
                throw new LoanSevaException('LoanSeva_Config__mdt.' + DEFAULT_RECORD + ' is missing');
            }
        }
        return cached;
    }

    /** Assumed monthly income per bucket, e.g. "Below 50K=40000;50K-1L=75000". */
    public static Map<String, Decimal> incomeValues() {
        Map<String, Decimal> values = new Map<String, Decimal>();
        for (String pair : String.valueOf(get().Income_Bucket_Values__c).split(';')) {
            List<String> parts = pair.split('=');
            if (parts.size() == 2) {
                values.put(parts[0].trim(), Decimal.valueOf(parts[1].trim()));
            }
        }
        return values;
    }

    public static List<Integer> tenureOptions() {
        List<Integer> options = new List<Integer>();
        for (String t : String.valueOf(get().Tenure_Options__c).split(',')) {
            options.add(Integer.valueOf(t.trim()));
        }
        options.sort();
        return options;
    }

    public static Integer maxOtpAttempts() {
        return Integer.valueOf(get().Max_OTP_Attempts__c);
    }

    public static Decimal rounding() {
        Decimal r = get().Amount_Rounding__c;
        return (r == null || r <= 0) ? 1 : r;
    }
}
