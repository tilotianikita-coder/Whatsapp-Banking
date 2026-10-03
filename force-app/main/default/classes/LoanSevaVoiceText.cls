/**
 * Turns a voice-note transcript into what the customer would have typed for the step they are on, so the
 * journey's own parsers and validation apply unchanged: "A B C P S one two three four K" -> ABCPS1234K,
 * "nine eight two zero..." -> 9820..., "priya at the rate gmail dot com" -> priya@gmail.com,
 * "August fifteenth nineteen ninety" -> 15 August 1990, "one lakh twenty thousand" -> 120000.
 * English number words are understood everywhere; spoken digits also in Hindi and Marathi.
 */
public with sharing class LoanSevaVoiceText {
    /** Steps where digits said one by one belong together (a mobile, OTP or PIN). */
    private static final Set<String> DIGIT_STATES = new Set<String>{ 'identity', 'otp', 'pincode' };
    private static final Set<String> AMOUNT_STATES = new Set<String>{ 'income', 'obligations', 'amount' };

    private static final Map<String, Integer> UNITS = new Map<String, Integer>{
        'zero' => 0, 'one' => 1, 'two' => 2, 'three' => 3, 'four' => 4, 'five' => 5, 'six' => 6, 'seven' => 7, 'eight' => 8, 'nine' => 9,
        'ten' => 10, 'eleven' => 11, 'twelve' => 12, 'thirteen' => 13, 'fourteen' => 14, 'fifteen' => 15, 'sixteen' => 16,
        'seventeen' => 17, 'eighteen' => 18, 'nineteen' => 19,
        'first' => 1, 'second' => 2, 'third' => 3, 'fourth' => 4, 'fifth' => 5, 'sixth' => 6, 'seventh' => 7, 'eighth' => 8, 'ninth' => 9,
        'tenth' => 10, 'eleventh' => 11, 'twelfth' => 12, 'thirteenth' => 13, 'fourteenth' => 14, 'fifteenth' => 15, 'sixteenth' => 16,
        'seventeenth' => 17, 'eighteenth' => 18, 'nineteenth' => 19,
        // Hindi / Marathi digits, Devanagari and romanised
        'शून्य' => 0, 'एक' => 1, 'दो' => 2, 'दोन' => 2, 'तीन' => 3, 'चार' => 4, 'पांच' => 5, 'पाँच' => 5, 'पाच' => 5, 'छह' => 6, 'छः' => 6,
        'सहा' => 6, 'सात' => 7, 'आठ' => 8, 'नौ' => 9, 'नऊ' => 9,
        'ek' => 1, 'teen' => 3, 'char' => 4, 'chaar' => 4, 'paanch' => 5, 'panch' => 5, 'chhe' => 6, 'chhah' => 6, 'saat' => 7, 'aath' => 8, 'nau' => 9
    };
    private static final Map<String, Integer> TENS = new Map<String, Integer>{
        'twenty' => 20, 'thirty' => 30, 'forty' => 40, 'fifty' => 50, 'sixty' => 60, 'seventy' => 70, 'eighty' => 80, 'ninety' => 90,
        'twentieth' => 20, 'thirtieth' => 30
    };
    /** Letters as they are said ("bee", "kay") or transcribed in Devanagari ("बी", "के"). Used only for the PAN. */
    private static final Map<String, String> LETTER_NAMES = new Map<String, String>{
        'AY' => 'A', 'BEE' => 'B', 'SEE' => 'C', 'SEA' => 'C', 'DEE' => 'D', 'EF' => 'F', 'GEE' => 'G', 'AITCH' => 'H', 'EYE' => 'I',
        'JAY' => 'J', 'KAY' => 'K', 'ELL' => 'L', 'EL' => 'L', 'EM' => 'M', 'EN' => 'N', 'PEE' => 'P', 'PEA' => 'P', 'CUE' => 'Q', 'QUEUE' => 'Q',
        'ARE' => 'R', 'AR' => 'R', 'ESS' => 'S', 'ES' => 'S', 'TEE' => 'T', 'TEA' => 'T', 'YOU' => 'U', 'VEE' => 'V', 'EX' => 'X',
        'WHY' => 'Y', 'ZED' => 'Z', 'ZEE' => 'Z',
        'ए' => 'A', 'बी' => 'B', 'सी' => 'C', 'डी' => 'D', 'ई' => 'E', 'एफ' => 'F', 'जी' => 'G', 'एच' => 'H', 'आई' => 'I', 'जे' => 'J',
        'के' => 'K', 'एल' => 'L', 'एम' => 'M', 'एन' => 'N', 'ओ' => 'O', 'पी' => 'P', 'क्यू' => 'Q', 'आर' => 'R', 'एस' => 'S', 'टी' => 'T',
        'यू' => 'U', 'वी' => 'V', 'डब्ल्यू' => 'W', 'एक्स' => 'X', 'वाई' => 'Y', 'जेड' => 'Z'
    };
    /** Words around a spoken PAN that are not part of it. */
    private static final Set<String> PAN_FILLER = new Set<String>{
        'MY', 'PAN', 'IS', 'NUMBER', 'NO', 'CARD', 'THE', 'IT', 'ITS', 'OK', 'OKAY', 'SO', 'UH', 'UM', 'AND', 'HAI', 'MERA', 'MERI', 'NUMBAR',
        'मेरा', 'पैन', 'नंबर', 'है', 'कार्ड', 'माझा', 'आहे', 'ओके'
    };
    private static final Map<String, String> AS_LETTER = new Map<String, String>{ '0' => 'O', '1' => 'I', '2' => 'Z', '5' => 'S', '6' => 'G', '8' => 'B' };
    private static final Map<String, String> AS_DIGIT = new Map<String, String>{ 'O' => '0', 'D' => '0', 'Q' => '0', 'I' => '1', 'L' => '1', 'Z' => '2', 'S' => '5', 'G' => '6', 'B' => '8', 'T' => '7' };
    private static final List<String> MONTHS = new List<String>{
        'january', 'february', 'march', 'april', 'may', 'june', 'july', 'august', 'september', 'october', 'november', 'december'
    };

    public static String forState(String transcript, String state) {
        String t = transcript == null ? '' : devanagariDigits(transcript).normalizeSpace();
        t = t.replaceAll('[.!?।]+$', '').trim();
        if (state == 'pan') {
            String pan = pan(t);
            return pan == null ? t : pan;
        }
        if (state == 'email') {
            return email(t);
        }
        if (state == 'company') {
            return t;
        }
        t = numbers(t);
        if (DIGIT_STATES.contains(state)) {
            t = t.replaceAll('(?<=[0-9])[\\s\\-]+(?=[0-9])', '');
        }
        if (state == 'identity') {
            t = t.replaceAll('(?i)\\b(and|aur|ani)\\b', ' ').normalizeSpace();
        }
        // "Option four" / "number 2" is a menu choice
        Matcher choice = Pattern.compile('(?i)^(?:option|number|choice|नंबर|ऑप्शन|पर्याय)?\\s*([0-9])$').matcher(t);
        if (choice.matches()) {
            return choice.group(1);
        }
        if (state == 'dob') {
            t = dob(t);
        }
        if (AMOUNT_STATES.contains(state)) {
            t = amount(t);
        }
        return t;
    }

    /** Number words to digits: "eighty five" -> 85, "double five" -> 5 5, "two hundred" -> 200. Other words are kept. */
    @TestVisible
    private static String numbers(String s) {
        List<String> tokens = s.replaceAll('(?<=\\p{L})-(?=\\p{L})', ' ').replaceAll('(?<![0-9]),|,(?![0-9])', ' ').normalizeSpace().split(' ');
        List<String> out = new List<String>();
        Integer repeat = 1;
        for (Integer i = 0; i < tokens.size(); i++) {
            String w = tokens[i].toLowerCase();
            if (w == 'double' || w == 'triple') {
                repeat = w == 'double' ? 2 : 3;
                continue;
            }
            Integer n = UNITS.get(w);
            if (TENS.containsKey(w)) {
                n = TENS.get(w);
                String next = i + 1 < tokens.size() ? tokens[i + 1].toLowerCase() : '';
                if (UNITS.containsKey(next) && UNITS.get(next) > 0 && UNITS.get(next) < 10) {
                    n += UNITS.get(next);
                    i++;
                }
            }
            if (n != null && i + 1 < tokens.size() && tokens[i + 1].toLowerCase() == 'hundred') {
                n *= 100;
                i++;
            }
            String value = n == null ? tokens[i] : String.valueOf(n);
            for (Integer r = 0; r < repeat; r++) {
                out.add(value);
            }
            repeat = 1;
        }
        return String.join(out, ' ');
    }

    /** Finds a PAN in what was said, letter by letter or in chunks, and fixes O/0, I/1, S/5... by position. */
    @TestVisible
    private static String pan(String s) {
        String direct = LoanSevaNewLoan.parsePan(s);
        if (direct != null) {
            return direct;
        }
        String u = numbers(s).toUpperCase().replaceAll('\\b([A-Z])\\s+(?:FOR|AS IN|SE)\\s+\\S+', '$1');
        String chars = '';
        for (String token : u.replaceAll('[^\\p{L}\\p{M}0-9\\s]', ' ').normalizeSpace().split(' ')) {
            if (PAN_FILLER.contains(token)) {
                continue;
            }
            if (LETTER_NAMES.containsKey(token)) {
                chars += LETTER_NAMES.get(token);
            } else if (Pattern.matches('[A-Z0-9]+', token) && (token.length() <= 5 || token.isNumeric())) {
                chars += token;
            }
        }
        for (Integer start = 0; start + 10 <= chars.length(); start++) {
            String candidate = repairPan(chars.substring(start, start + 10));
            if (LoanSevaNewLoan.PAN_FORMAT.matcher(candidate).matches()) {
                return candidate;
            }
        }
        return null;
    }

    private static String repairPan(String c) {
        String out = '';
        for (Integer i = 0; i < c.length(); i++) {
            String ch = c.substring(i, i + 1);
            Boolean letter = i < 5 || i == 9;
            String fixed = letter ? AS_LETTER.get(ch) : AS_DIGIT.get(ch);
            out += fixed == null ? ch : fixed;
        }
        return out;
    }

    @TestVisible
    private static String email(String s) {
        if (Pattern.compile('[A-Za-z0-9._%+\\-]+@[A-Za-z0-9.\\-]+\\.[A-Za-z]{2,}').matcher(s).find()) {
            return s;
        }
        String t = (' ' + s.toLowerCase() + ' ')
            .replaceAll('^\\s*(my )?(e-?mail|ईमेल|ई-मेल)( id| address| आईडी)?( is| है| आहे)?\\s+', ' ')
            .replaceAll('\\s(at the rate of|at the rate|at rate|at|एट द रेट|एट)\\s', '@')
            .replaceAll('\\s(dot|डॉट)\\s', '.')
            .replaceAll('\\s(underscore)\\s', '_')
            .replaceAll('\\s(dash|hyphen)\\s', '-');
        return t.replaceAll('\\s+', '');
    }

    /** "August 15 1990" -> "15 August 1990"; "19 90" -> 1990 (years are said as two numbers). */
    @TestVisible
    private static String dob(String s) {
        String t = s.replaceAll('(?i)\\b(19|20) ([0-9]{2})\\b', '$1$2');
        Matcher m = Pattern.compile('(?i)\\b(' + String.join(MONTHS, '|') + ')\\s+([0-9]{1,2})(?:st|nd|rd|th)?,?\\s+([0-9]{4})').matcher(t);
        if (m.find()) {
            t = m.group(2) + ' ' + m.group(1) + ' ' + m.group(3);
        }
        return t.replaceAll('(?i)\\b(of|the)\\b', ' ').normalizeSpace();
    }

    /** "1 lakh 20 thousand" -> 120000, which parseAmount reads in one go. */
    @TestVisible
    private static String amount(String s) {
        Matcher m = Pattern.compile('(?i)([0-9]+(?:\\.[0-9]+)?)\\s*(?:lakhs?|lacs?|लाख)\\s*(?:and\\s+)?([0-9]+)\\s*(?:thousand|k|हजार|हज़ार)').matcher(s);
        if (m.find()) {
            Decimal total = Decimal.valueOf(m.group(1)) * 100000 + Decimal.valueOf(m.group(2)) * 1000;
            return s.substring(0, m.start()) + String.valueOf(total.intValue()) + s.substring(m.end());
        }
        return s;
    }

    private static String devanagariDigits(String s) {
        String out = s;
        List<String> digits = new List<String>{ '०', '१', '२', '३', '४', '५', '६', '७', '८', '९' };
        for (Integer i = 0; i < digits.size(); i++) {
            out = out.replace(digits[i], String.valueOf(i));
        }
        return out;
    }
}
