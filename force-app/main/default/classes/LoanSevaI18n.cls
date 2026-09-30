/**
 * Customer-facing copy in English / Hindi / Marathi, sourced from LoanSeva_Message__mdt,
 * plus Indian-style number and date formatting.
 * SOQL is used (not getInstance) because getInstance truncates long text areas to 255 chars.
 */
public with sharing class LoanSevaI18n {
    public static final String EN = 'EN';
    public static final String HI = 'HI';
    public static final String MR = 'MR';
    public static final String TIMEZONE = 'Asia/Kolkata';

    private static Map<String, LoanSeva_Message__mdt> messages;

    public static String msg(String key, String lang) {
        return msg(key, lang, null);
    }

    public static String msg(String key, String lang, Map<String, Object> tokens) {
        LoanSeva_Message__mdt m = all().get(key);
        if (m == null) {
            throw new LoanSevaException('Missing LoanSeva_Message__mdt: ' + key);
        }
        return mergeTokens(pick(m.English__c, m.Hindi__c, m.Marathi__c, lang), tokens);
    }

    // params are not named en/hi/mr: Apex is case-insensitive, so they would shadow EN/HI/MR
    public static String pick(String english, String hindi, String marathi, String lang) {
        String text = english;
        if (lang == HI && String.isNotBlank(hindi)) {
            text = hindi;
        } else if (lang == MR && String.isNotBlank(marathi)) {
            text = marathi;
        }
        return text == null ? '' : text;
    }

    public static String mergeTokens(String text, Map<String, Object> tokens) {
        if (tokens == null || text == null) {
            return text;
        }
        for (String k : tokens.keySet()) {
            Object v = tokens.get(k);
            text = text.replace('{' + k + '}', v == null ? '' : String.valueOf(v));
        }
        return text;
    }

    private static Map<String, LoanSeva_Message__mdt> all() {
        if (messages == null) {
            messages = new Map<String, LoanSeva_Message__mdt>();
            for (LoanSeva_Message__mdt m : [
                SELECT DeveloperName, English__c, Hindi__c, Marathi__c
                FROM LoanSeva_Message__mdt
            ]) {
                messages.put(m.DeveloperName, m);
            }
        }
        return messages;
    }

    /** Normalises a language choice ("HI", "hindi", "हिंदी", "MR", "marathi") to EN/HI/MR, or null. */
    public static String parseLanguage(String input) {
        if (String.isBlank(input)) {
            return null;
        }
        String s = input.trim().toLowerCase();
        if (s == 'hi' || s.contains('hindi') || s.contains('हिंदी') || s.contains('हिन्दी')) {
            return HI;
        }
        if (s == 'mr' || s.contains('marathi') || s.contains('मराठी')) {
            return MR;
        }
        if (s == 'en' || s.contains('english') || s.contains('अंग्रेज़ी') || s.contains('इंग्रजी')) {
            return EN;
        }
        return null;
    }

    /** ₹5,00,000 (Indian digit grouping, no decimals). */
    public static String inr(Decimal amount) {
        if (amount == null) {
            return '';
        }
        Long value = amount.setScale(0, RoundingMode.HALF_UP).longValue();
        Boolean negative = value < 0;
        String digits = String.valueOf(Math.abs(value));
        String result;
        if (digits.length() <= 3) {
            result = digits;
        } else {
            result = digits.substring(digits.length() - 3);
            String rest = digits.substring(0, digits.length() - 3);
            while (rest.length() > 2) {
                result = rest.substring(rest.length() - 2) + ',' + result;
                rest = rest.substring(0, rest.length() - 2);
            }
            result = rest + ',' + result;
        }
        return (negative ? '-' : '') + '₹' + result;
    }

    /** ₹5L / ₹2.5L / ₹1.2Cr / ₹75,000 for compact summaries. */
    public static String inrShort(Decimal amount) {
        if (amount == null) {
            return '';
        }
        if (amount >= 10000000) {
            return '₹' + trimZeros((amount / 10000000).setScale(2, RoundingMode.DOWN)) + 'Cr';
        }
        if (amount >= 100000) {
            return '₹' + trimZeros((amount / 100000).setScale(2, RoundingMode.DOWN)) + 'L';
        }
        return inr(amount);
    }

    private static String trimZeros(Decimal d) {
        String s = d.toPlainString();
        if (s.contains('.')) {
            s = s.replaceAll('0+$', '').removeEnd('.');
        }
        return s;
    }

    public static String formatDateTime(Datetime dt) {
        return dt == null ? '' : dt.format('EEE, d MMM · h:mm a', TIMEZONE);
    }

    public static Date todayIst() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', TIMEZONE));
    }

    /** Builds a Datetime for an IST wall-clock time. */
    public static Datetime istDateTime(Date d, Integer hour, Integer minute) {
        return Datetime.newInstanceGmt(d.year(), d.month(), d.day(), hour, minute, 0).addMinutes(-330);
    }

    public static Integer istHour(Datetime dt) {
        return Integer.valueOf(dt.format('H', TIMEZONE));
    }
}
