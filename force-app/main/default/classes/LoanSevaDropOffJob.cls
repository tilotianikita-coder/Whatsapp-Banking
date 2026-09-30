/**
 * Drop-off detection and re-engagement. Runs every Job_Interval_Minutes__c and reschedules itself
 * (a scheduled flow cannot run at minute granularity, which the demo needs).
 *
 *  1. Active journeys idle for Idle_Minutes_Before_Drop__c -> Dropped, drop point recorded, RM task with the intent summary.
 *  2. Dropped journeys get re-engagement nudge 1 at Dropped_At + Nudge_1_Delay and nudge 2 at Dropped_At + Nudge_2_Delay
 *     (demo 2 / 5 minutes; production 24h / 72h). A customer reply re-activates the journey (LoanSevaJourneyService.touch).
 *
 * Start: LoanSevaDropOffJob.start();   Stop: LoanSevaDropOffJob.stop();
 */
public with sharing class LoanSevaDropOffJob implements Schedulable {
    public static final String JOB_PREFIX = 'LoanSeva Drop-off';
    @TestVisible
    private static final Integer BATCH_LIMIT = 200;

    public void execute(SchedulableContext ctx) {
        run();
        if (ctx != null) {
            System.abortJob(ctx.getTriggerId());
            scheduleNext();
        }
    }

    public static void run() {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Datetime now = Datetime.now();
        markDropped(now, cfg);
        sendReengagement(now, cfg);
    }

    @TestVisible
    private static void markDropped(Datetime now, LoanSeva_Config__mdt cfg) {
        Integer idle = cfg.Idle_Minutes_Before_Drop__c == null ? 30 : cfg.Idle_Minutes_Before_Drop__c.intValue();
        Datetime cutoff = now.addMinutes(-idle);
        List<Loan_Journey__c> stale = Database.query(
            'SELECT ' + LoanSevaJourneyService.journeyFields() + ' FROM Loan_Journey__c ' +
            'WHERE Status__c = \'Active\' AND Last_Activity__c < :cutoff ORDER BY Last_Activity__c ASC LIMIT :BATCH_LIMIT'
        );
        if (stale.isEmpty()) {
            return;
        }
        Integer delay1 = cfg.Nudge_1_Delay_Minutes__c == null ? 1440 : cfg.Nudge_1_Delay_Minutes__c.intValue();
        List<Task> tasks = new List<Task>();
        for (Loan_Journey__c j : stale) {
            j.Status__c = LoanSevaJourneyService.STATUS_DROPPED;
            j.Dropped_At__c = now;
            j.Drop_Point__c = j.Stage__c + ' (' + LoanSevaJourneyService.fieldsCompleted(j) + '/5 fields)';
            j.Fields_Completed__c = LoanSevaJourneyService.fieldsCompleted(j);
            j.Intent_Summary__c = LoanSevaJourneyService.intentSummary(j).abbreviate(255);
            j.Next_Nudge_At__c = now.addMinutes(delay1);
            if (j.Nudges_Sent__c == null) {
                j.Nudges_Sent__c = 0;
            }
            if (j.RM_Followup_Created__c != true) {
                tasks.add(LoanSevaJourneyService.buildRmTask(
                    j,
                    'Drop-off at ' + j.Stage__c + ' — ' + LoanSevaJourneyService.intentSummary(j),
                    'Customer went quiet at stage ' + j.Drop_Point__c + '. Everything captured so far is on the journey.\n' +
                        LoanSevaJourneyService.rmDescription(j),
                    null
                ));
                j.RM_Followup_Created__c = true;
            }
        }
        insert tasks;
        update stale;
    }

    @TestVisible
    private static void sendReengagement(Datetime now, LoanSeva_Config__mdt cfg) {
        List<Loan_Journey__c> due = Database.query(
            'SELECT ' + LoanSevaJourneyService.journeyFields() + ' FROM Loan_Journey__c ' +
            'WHERE Status__c = \'Dropped\' AND Next_Nudge_At__c <= :now AND Consent_WhatsApp__c = TRUE ' +
            'AND (Nudges_Sent__c = null OR Nudges_Sent__c < 2) ORDER BY Next_Nudge_At__c ASC LIMIT :BATCH_LIMIT'
        );
        if (due.isEmpty()) {
            return;
        }
        Integer delay1 = cfg.Nudge_1_Delay_Minutes__c == null ? 1440 : cfg.Nudge_1_Delay_Minutes__c.intValue();
        Integer delay2 = cfg.Nudge_2_Delay_Minutes__c == null ? 4320 : cfg.Nudge_2_Delay_Minutes__c.intValue();
        List<LoanSevaWhatsAppSender.Outbound> outbound = new List<LoanSevaWhatsAppSender.Outbound>();
        for (Loan_Journey__c j : due) {
            Integer sent = j.Nudges_Sent__c == null ? 0 : j.Nudges_Sent__c.intValue();
            outbound.add(new LoanSevaWhatsAppSender.Outbound(j.Id, reengageText(j, sent + 1), cfg.Reengage_Definition__c));
            j.Nudges_Sent__c = sent + 1;
            // nudge 2 is measured from the drop, like T+24h / T+72h
            Datetime dropped = j.Dropped_At__c == null ? now : j.Dropped_At__c;
            j.Next_Nudge_At__c = sent == 0 ? dropped.addMinutes(Math.max(delay2, delay1 + 1)) : null;
        }
        update due;
        LoanSevaWhatsAppSender.enqueue(outbound);
    }

    public static String reengageText(Loan_Journey__c j, Integer nudgeNumber) {
        String purpose = '';
        if (j.Language__c == LoanSevaI18n.EN && String.isNotBlank(j.Purpose__c) && j.Purpose__c != 'Other') {
            purpose = ' for ' + j.Purpose__c.toLowerCase();
        }
        return LoanSevaI18n.msg(nudgeNumber == 1 ? 'Reengage_1' : 'Reengage_2', j.Language__c, new Map<String, Object>{
            'name' => LoanSevaJourneyService.firstName(j),
            'purpose' => purpose
        });
    }

    // ------------------------------------------------------------------ scheduling
    public static Id start() {
        stop();
        return scheduleNext();
    }

    public static void stop() {
        String pattern = JOB_PREFIX + '%';
        for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern]) {
            System.abortJob(ct.Id);
        }
    }

    private static Id scheduleNext() {
        LoanSeva_Config__mdt cfg = LoanSevaConfig.get();
        Integer interval = cfg.Job_Interval_Minutes__c == null ? 60 : Math.max(1, cfg.Job_Interval_Minutes__c.intValue());
        Datetime next = Datetime.now().addMinutes(interval);
        String cron = next.second() + ' ' + next.minute() + ' ' + next.hour() + ' ' + next.day() + ' ' + next.month() + ' ? ' + next.year();
        return System.schedule(JOB_PREFIX + ' ' + next.getTime(), cron, new LoanSevaDropOffJob());
    }
}
