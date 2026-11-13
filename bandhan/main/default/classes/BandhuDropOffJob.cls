/**
 * Drop-off detection for Bandhu card journeys: an Active journey idle for Idle_Minutes__c (demo 2, production e.g. 30)
 * becomes Dropped with its drop point, the prospect Lead is re-scored and the RM gets a call task (BandhuLeadService).
 * Reschedules itself every minute (a scheduled flow cannot run at minute granularity, which the demo needs).
 *
 * Start: BandhuDropOffJob.start();   Stop: BandhuDropOffJob.stop();
 */
public with sharing class BandhuDropOffJob implements Schedulable {
    public static final String JOB_PREFIX = 'Bandhu Drop-off';
    private static final Set<String> TERMINAL = new Set<String>{ 'done', 'menu' };

    public void execute(SchedulableContext ctx) {
        run();
        if (ctx != null) {
            System.abortJob(ctx.getTriggerId());
            scheduleNext();
        }
    }

    public static void run() {
        Bandhu_Config__mdt cfg = BandhuConfig.get();
        Integer idle = cfg.Idle_Minutes__c == null ? 30 : cfg.Idle_Minutes__c.intValue();
        Datetime cutoff = Datetime.now().addMinutes(-idle);
        List<Card_Journey__c> stale = new List<Card_Journey__c>();
        for (Card_Journey__c j : [SELECT Id FROM Card_Journey__c WHERE Status__c = 'Active' AND Last_Activity__c < :cutoff ORDER BY Last_Activity__c ASC LIMIT 20]) {
            Card_Journey__c full = BandhuJourneyService.byId(j.Id);
            if (!TERMINAL.contains(full.Step__c) && String.isNotBlank(full.Step__c)) {
                full.Status__c = BandhuJourneyService.STATUS_DROPPED;
                full.Dropped_At__c = Datetime.now();
                full.Drop_Point__c = BandhuLeadService.stepLabel(full) + ' (' + BandhuJourneyService.fieldsDone(full) + '/10 details)';
                stale.add(full);
            }
        }
        if (stale.isEmpty()) {
            return;
        }
        update stale;
        BandhuLeadService.captureDropOffs(stale);
        update stale;
    }

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
        Datetime next = Datetime.now().addMinutes(1);
        String cron = next.second() + ' ' + next.minute() + ' ' + next.hour() + ' ' + next.day() + ' ' + next.month() + ' ? ' + next.year();
        return System.schedule(JOB_PREFIX + ' ' + next.getTime(), cron, new BandhuDropOffJob());
    }
}
