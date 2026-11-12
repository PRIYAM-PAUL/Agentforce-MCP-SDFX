/**
 * Fonada MCP - repeat-launch guard and launch log shared by the Start Campaign (voice)
 * and Send Message Campaign (WhatsApp / RCS) actions.
 *
 * Each launch is logged in Fonada_Campaign_Launch__c (package-owned log, system mode).
 * Starting the same source with the same Fonada agent or template again within
 * Fonada Settings → Repeat launch guard (default 10 minutes) is refused unless the user
 * explicitly confirms. Log records are inserted after all callouts (flush), because DML
 * before a callout in the same transaction is not allowed. Reading or writing the log
 * never blocks or fails a launch.
 */
public without sharing class FonadaLaunchGuard {

    private static final String TZ = 'Asia/Kolkata';
    private static List<Fonada_Campaign_Launch__c> pending = new List<Fonada_Campaign_Launch__c>();

    /** Call at the start of an invocable batch. */
    public static void reset() {
        pending = new List<Fonada_Campaign_Launch__c>();
    }

    /**
     * Message when sourceKey + agentKey was launched within the guard window; null when fine.
     * @param what       e.g. 'a Fonada campaign for Campaign X with agent main_bot'
     * @param actionName the agent action to call again with allowRepeat = true
     */
    public static String check(String sourceKey, String agentKey, String what, String actionName) {
        Integer minutes = FonadaSettings.repeatGuardMinutes();
        if (minutes <= 0 || String.isBlank(sourceKey) || String.isBlank(agentKey)) return null;
        for (Fonada_Campaign_Launch__c p : pending) {
            if (p.Source_Id__c == sourceKey && p.Fonada_Agent__c != null && p.Fonada_Agent__c.equalsIgnoreCase(agentKey)) {
                return text(what, 'just now', p.Fonada_Campaign_Id__c, actionName, minutes);
            }
        }
        try {
            List<Fonada_Campaign_Launch__c> recent = (List<Fonada_Campaign_Launch__c>) Database.queryWithBinds(
                'SELECT Id, CreatedDate, Fonada_Campaign_Id__c FROM Fonada_Campaign_Launch__c'
                + ' WHERE Source_Id__c = :sourceKey AND Fonada_Agent__c = :agentKey AND CreatedDate >= :since'
                + ' ORDER BY CreatedDate DESC LIMIT 1',
                new Map<String, Object>{
                    'sourceKey' => sourceKey, 'agentKey' => agentKey, 'since' => Datetime.now().addMinutes(-minutes)
                }, AccessLevel.SYSTEM_MODE);
            if (recent.isEmpty()) return null;
            return text(what, 'at ' + recent[0].CreatedDate.format('HH:mm', TZ) + ' IST',
                recent[0].Fonada_Campaign_Id__c, actionName, minutes);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'FonadaMCP: repeat-launch check skipped: ' + e.getMessage());
            return null;
        }
    }

    private static String text(String what, String whenText, String fonadaId, String actionName, Integer minutes) {
        return 'Not started: ' + what + ' was already started ' + whenText
            + (fonadaId == null ? '' : ' (Fonada campaign id ' + fonadaId + ')')
            + '. Starting it again would contact the same people twice. Tell the user; only if they explicitly '
            + 'confirm a second run, call ' + actionName + ' again with allowRepeat = true (or wait ' + minutes
            + ' minutes).';
    }

    /** True when the request explicitly allows a repeat. */
    public static Boolean allowsRepeat(String allowRepeat) {
        return allowRepeat != null && allowRepeat.trim().toLowerCase() == 'true';
    }

    /** Queues a log record; written by flush(). */
    public static void record(String channel, String sourceKey, String sourceName, String agentKey,
                              String fonadaId, String fonadaName, String schedule, Integer people) {
        pending.add(new Fonada_Campaign_Launch__c(
            Channel__c = channel,
            Source_Id__c = sourceKey == null ? null : sourceKey.left(18),
            Source_Name__c = sourceName == null ? null : sourceName.left(255),
            Fonada_Agent__c = agentKey == null ? null : agentKey.left(100),
            Fonada_Campaign_Id__c = fonadaId == null ? null : fonadaId.left(100),
            Fonada_Campaign_Name__c = fonadaName == null ? null : fonadaName.left(255),
            Schedule__c = schedule == null ? null : schedule.left(100),
            People_Queued__c = people));
    }

    /** Inserts the queued log records. Call after all callouts. Never throws. */
    public static void flush() {
        if (pending.isEmpty()) return;
        try {
            Database.insert(pending, AccessLevel.SYSTEM_MODE);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'FonadaMCP: could not log the launch: ' + e.getMessage());
        }
        pending = new List<Fonada_Campaign_Launch__c>();
    }
}
