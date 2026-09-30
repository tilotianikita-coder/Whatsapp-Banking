/**
 * Lightweight parser for customer-typed callback times (IST), e.g.
 * "Thu 11:00", "tomorrow 4pm", "today 5:30 pm", "2 Oct 11am", "02/10 15:00".
 * Returns null when no time of day can be found.
 */
public with sharing class LoanSevaDateParser {
    private static final List<String> DAYS = new List<String>{ 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun' };
    private static final List<String> MONTHS = new List<String>{
        'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'
    };

    public static Datetime parse(String input) {
        if (String.isBlank(input)) {
            return null;
        }
        String s = input.toLowerCase().trim();
        Integer[] hm = parseTime(s);
        if (hm == null) {
            return null;
        }
        Date today = LoanSevaI18n.todayIst();
        Date day = parseDay(s, today);
        Datetime result = LoanSevaI18n.istDateTime(day == null ? today : day, hm[0], hm[1]);
        if (day == null && result < Datetime.now()) {
            result = LoanSevaI18n.istDateTime(today.addDays(1), hm[0], hm[1]);
        }
        return result;
    }

    private static Integer[] parseTime(String s) {
        // 4pm, 4 pm, 11:30am, 11.30 am
        Matcher ampm = Pattern.compile('\\b(\\d{1,2})(?:[:.](\\d{2}))?\\s*(am|pm)\\b').matcher(s);
        if (ampm.find()) {
            Integer h = Integer.valueOf(ampm.group(1));
            Integer m = ampm.group(2) == null ? 0 : Integer.valueOf(ampm.group(2));
            if (h < 1 || h > 12 || m > 59) {
                return null;
            }
            if (ampm.group(3) == 'pm' && h < 12) {
                h += 12;
            } else if (ampm.group(3) == 'am' && h == 12) {
                h = 0;
            }
            return new Integer[]{ h, m };
        }
        // 15:00, 11:00 (24h)
        Matcher h24 = Pattern.compile('\\b(\\d{1,2})[:.](\\d{2})\\b').matcher(s);
        if (h24.find()) {
            Integer h = Integer.valueOf(h24.group(1));
            Integer m = Integer.valueOf(h24.group(2));
            if (h > 23 || m > 59) {
                return null;
            }
            // "4:00" during a callback conversation almost always means the afternoon
            if (h >= 1 && h <= 7) {
                h += 12;
            }
            return new Integer[]{ h, m };
        }
        return null;
    }

    private static Date parseDay(String s, Date today) {
        if (s.contains('today') || s.contains('आज')) {
            return today;
        }
        if (s.contains('day after tomorrow') || s.contains('परसों') || s.contains('परवा')) {
            return today.addDays(2);
        }
        if (s.contains('tomorrow') || s.contains('tmrw') || s.contains('कल') || s.contains('उद्या')) {
            return today.addDays(1);
        }
        // "2 oct" / "oct 2"
        for (Integer i = 0; i < MONTHS.size(); i++) {
            Matcher m = Pattern.compile('\\b(\\d{1,2})\\s*' + MONTHS[i] + '|' + MONTHS[i] + '[a-z]*\\s*(\\d{1,2})\\b').matcher(s);
            if (m.find()) {
                Integer dayNum = Integer.valueOf(m.group(1) != null ? m.group(1) : m.group(2));
                return rollForward(today, i + 1, dayNum);
            }
        }
        // "02/10" (dd/mm)
        Matcher dm = Pattern.compile('\\b(\\d{1,2})/(\\d{1,2})\\b').matcher(s);
        if (dm.find()) {
            return rollForward(today, Integer.valueOf(dm.group(2)), Integer.valueOf(dm.group(1)));
        }
        // weekday names -> next occurrence (today counts if named)
        Integer todayIdx = DAYS.indexOf(Datetime.newInstanceGmt(today, Time.newInstance(12, 0, 0, 0)).formatGmt('EEE').toLowerCase());
        for (Integer i = 0; i < DAYS.size(); i++) {
            if (Pattern.compile('\\b' + DAYS[i]).matcher(s).find()) {
                Integer delta = Math.mod(i - todayIdx + 7, 7);
                return today.addDays(delta);
            }
        }
        return null;
    }

    private static Date rollForward(Date today, Integer month, Integer dayNum) {
        if (month < 1 || month > 12 || dayNum < 1 || dayNum > Date.daysInMonth(today.year(), month)) {
            return null;
        }
        Date d = Date.newInstance(today.year(), month, dayNum);
        return d < today ? Date.newInstance(today.year() + 1, month, dayNum) : d;
    }
}
