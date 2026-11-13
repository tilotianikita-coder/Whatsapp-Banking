/**
 * Bandhu copy in English / Hindi / Bengali (Bandhu_Message__mdt), option lists, and Indian number, date and
 * mobile formats. SOQL rather than getInstance: getInstance truncates long text areas to 255 characters.
 */
public inherited sharing class BandhuI18n {
    public static final String EN = 'EN';
    public static final String HI = 'HI';
    public static final String BN = 'BN';
    public static final String TIMEZONE = 'Asia/Kolkata';

    private static Map<String, Bandhu_Message__mdt> messages;

    public static String msg(String key, String lang) {
        return msg(key, lang, null);
    }

    public static String msg(String key, String lang, Map<String, Object> tokens) {
        Bandhu_Message__mdt m = all().get(key);
        if (m == null) {
            throw new BandhuException('Missing Bandhu_Message__mdt: ' + key);
        }
        return mergeTokens(pick(m.English__c, m.Hindi__c, m.Bengali__c, lang), tokens);
    }

    public static Boolean has(String key) {
        return all().containsKey(key);
    }

    /** An option list (Opt_* message, one option per line). */
    public static List<String> options(String key, String lang, Map<String, Object> tokens) {
        List<String> result = new List<String>();
        for (String line : msg(key, lang, tokens).split('\n')) {
            if (String.isNotBlank(line)) {
                result.add(line.trim());
            }
        }
        return result;
    }

    // params are not named en/hi/bn: Apex is case-insensitive, so they would shadow EN/HI/BN
    public static String pick(String english, String hindi, String bengali, String lang) {
        String text = english;
        if (lang == HI && String.isNotBlank(hindi)) {
            text = hindi;
        } else if (lang == BN && String.isNotBlank(bengali)) {
            text = bengali;
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

    private static Map<String, Bandhu_Message__mdt> all() {
        if (messages == null) {
            messages = new Map<String, Bandhu_Message__mdt>();
            for (Bandhu_Message__mdt m : [SELECT DeveloperName, English__c, Hindi__c, Bengali__c FROM Bandhu_Message__mdt]) {
                messages.put(m.DeveloperName, m);
            }
        }
        return messages;
    }

    /** "HI", "hindi", "हिंदी", "BN", "bangla", "বাংলা", "EN", "english" -> EN/HI/BN, or null. */
    public static String parseLanguage(String input) {
        if (String.isBlank(input)) {
            return null;
        }
        String s = input.trim().toLowerCase();
        if (s == 'hi' || s.contains('hindi') || s.contains('हिंदी') || s.contains('हिन्दी')) {
            return HI;
        }
        if (s == 'bn' || s.contains('bengali') || s.contains('bangla') || s.contains('বাংলা')) {
            return BN;
        }
        if (s == 'en' || s.contains('english') || s.contains('अंग्रेज़ी') || s.contains('ইংরেজি')) {
            return EN;
        }
        return null;
    }

    /** ₹1,50,000 (Indian digit grouping, no decimals). */
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

    /** ₹2 lakh / ₹1.5 lakh / ₹75,000 for summaries. */
    public static String inrShort(Decimal amount) {
        if (amount == null) {
            return '';
        }
        if (amount >= 100000) {
            String s = (amount / 100000).setScale(2, RoundingMode.DOWN).toPlainString();
            s = s.contains('.') ? s.replaceAll('0+$', '').removeEnd('.') : s;
            return '₹' + s + ' lakh';
        }
        return inr(amount);
    }

    /** "85000", "85,000", "85k", "1.2 lakh", "₹1,20,000", "1.2L" -> rupees; a bare number under 1,000 is not an amount. */
    public static Decimal parseAmount(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        String t = s.toLowerCase().replace(',', '').replace('₹', '').replace('rs.', ' ').replace('inr', ' ')
            .replace('लाख', 'lakh').replace('লাখ', 'lakh').replace('हज़ार', 'k').replace('हजार', 'k').replace('হাজার', 'k');
        Matcher m = Pattern.compile('([0-9]+(?:\\.[0-9]+)?)\\s*(lakhs|lakh|lacs|lac|l|k|thousand)?(?![a-z])').matcher(t);
        if (!m.find()) {
            return null;
        }
        Decimal value = Decimal.valueOf(m.group(1));
        String unit = m.group(2);
        if (unit == null) {
            return value >= 1000 ? value : null;
        }
        return unit.startsWith('l') ? value * 100000 : value * 1000;
    }

    /** Last 10 digits of an Indian mobile; null if it isn't one. */
    public static String normalizeMobile(String raw) {
        String digits = raw == null ? '' : raw.replaceAll('[^0-9]', '');
        if (digits.length() == 12 && digits.startsWith('91')) {
            digits = digits.substring(2);
        } else if (digits.length() == 11 && digits.startsWith('0')) {
            digits = digits.substring(1);
        }
        return Pattern.matches('[6-9][0-9]{9}', digits) ? digits : null;
    }

    public static List<String> mobileVariants(String mobile10) {
        return new List<String>{ mobile10, '+91' + mobile10, '91' + mobile10, '+91 ' + mobile10, '0' + mobile10 };
    }

    public static String maskMobile(String mobile10) {
        return mobile10 == null ? '' : '+91 XXXXXX' + mobile10.right(4);
    }

    public static String maskPan(String pan) {
        return String.isBlank(pan) ? '' : 'XXXXX' + pan.right(5);
    }

    public static Date today() {
        return Date.valueOf(Datetime.now().format('yyyy-MM-dd', TIMEZONE));
    }

    public static String formatDate(Date d) {
        return d == null ? '' : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('dd/MM/yyyy');
    }
}
