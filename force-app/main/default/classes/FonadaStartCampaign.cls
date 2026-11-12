/**
 * Fonada MCP - Agentforce action: start a Fonada outbound voice campaign for the
 * people in a Salesforce Campaign or Account, or call one person (a Contact or Lead
 * Id from find_crm_record, or a phone number the user typed). Single and bulk calls
 * both go through voice_campaigns_create_outbound.
 *
 * Builds the call list in Apex (FonadaGetCallList.collect) and calls the Fonada
 * tool voice_campaigns_create_outbound itself with an exact payload, so the LLM
 * only passes plain text (which campaign/account, which Fonada agent, optional
 * schedule). CRM reads follow FonadaGetCallList (system mode only for Agentforce
 * agent users, user mode for people; Do Not Call skipped); the Fonada call uses
 * the packaged named credential.
 *
 * Repeat-launch guard: each started campaign is logged in Fonada_Campaign_Launch__c
 * (package-owned log, written in system mode). Starting the same source with the same
 * Fonada agent again within Fonada Settings → Repeat launch guard (default 10 minutes)
 * is refused unless allowRepeat = true, so a retry or a repeated "yes" never calls
 * everyone twice.
 */
global without sharing class FonadaStartCampaign {

    global class Request {
        @InvocableVariable(label='Fonada agent' description='Name of the Fonada outbound (telephony) agent that makes the calls' required=true)
        global String fonadaAgent;
        @InvocableVariable(label='Campaign name' description='Salesforce Campaign whose contact and lead members should be called')
        global String campaignName;
        @InvocableVariable(label='Account name' description='Salesforce Account whose contacts should be called (when no campaign is given)')
        global String accountName;
        @InvocableVariable(label='Fonada campaign title' description='Optional name for the Fonada campaign. Defaults to the Salesforce source plus date and time.')
        global String campaignTitle;
        @InvocableVariable(label='Schedule day' description='Optional dial day YYYY-MM-DD (IST). Defaults to today.')
        global String scheduleDay;
        @InvocableVariable(label='Start time' description='Optional dial window start HH:MM (IST). Defaults to now.')
        global String startTime;
        @InvocableVariable(label='End time' description='Optional dial window end HH:MM (IST). Defaults to 3 hours after the start, at most 23:59.')
        global String endTime;
        @InvocableVariable(label='Max records' description='Maximum number of people to call (default 200, max 1000)')
        global String maxRecords;
        @InvocableVariable(label='Record Id' description='Id of the Salesforce Campaign or Account (sourceId from get_crm_call_list), or of one Contact or Lead (recordId from find_crm_record) for a single call. Takes priority over the names.')
        global String recordId;
        @InvocableVariable(label='Phone number' description='Only for a person who is not in Salesforce: the phone number the user typed. Ignored when a campaign, account or recordId is given.')
        global String phoneNumber;
        @InvocableVariable(label='Person name' description='Name of the person for a direct phone number call')
        global String personName;
        @InvocableVariable(label='Allow repeat' description='true only when the user explicitly confirmed starting the same Salesforce Campaign or Account again with the same Fonada agent within a few minutes of an earlier start.')
        global String allowRepeat;
    }

    global class Result {
        @InvocableVariable(label='Success' description='true when Fonada accepted the campaign')
        global String success;
        @InvocableVariable(label='Fonada campaign name' description='Name of the created Fonada campaign')
        global String fonadaCampaignName;
        @InvocableVariable(label='Fonada campaign id' description='Id of the created Fonada campaign')
        global String fonadaCampaignId;
        @InvocableVariable(label='People queued' description='Number of people sent to the dialer')
        global String peopleQueued;
        @InvocableVariable(label='Skipped' description='People skipped (no phone, duplicate or over the limit)')
        global String skipped;
        @InvocableVariable(label='Schedule' description='Dial window used (IST)')
        global String schedule;
        @InvocableVariable(label='Message' description='Plain-language result or the exact error from Fonada')
        global String message;
    }

    private static final Pattern DAY_FORMAT = Pattern.compile('^\\d{4}-\\d{2}-\\d{2}$');
    private static final Pattern TIME_FORMAT = Pattern.compile('^([01]?\\d|2[0-3]):[0-5]\\d$');
    private static final String TZ = 'Asia/Kolkata';
    private static final Integer TITLE_LENGTH = 120;

    @InvocableMethod(label='Fonada: Start Campaign'
        description='Starts a Fonada outbound voice campaign that calls the people in a Salesforce Campaign or Account, or one Contact, Lead or phone number, with the given Fonada agent.'
        category='Fonada MCP' callout=true)
    global static List<Result> start(List<Request> requests) {
        List<Result> results = new List<Result>();
        FonadaLaunchGuard.reset();
        for (Request r : requests) results.add(startOne(r));
        FonadaLaunchGuard.flush();   // after all callouts: DML before a callout is not allowed
        return results;
    }

    private static Result startOne(Request req) {
        Result res = new Result();
        res.success = 'false';
        res.peopleQueued = '0';
        res.skipped = '0';
        if (req == null || String.isBlank(req.fonadaAgent)) {
            res.message = 'Ask the user which Fonada telephony agent should make the calls (use voice_list_agents).';
            return res;
        }
        String agent = FonadaSettings.cleanText(req.fonadaAgent, 100);

        Boolean direct = String.isBlank(req.campaignName) && String.isBlank(req.accountName)
            && String.isBlank(req.recordId) && String.isNotBlank(req.phoneNumber);
        FonadaGetCallList.CallList cl = direct
            ? FonadaGetCallList.directCall(req.phoneNumber, req.personName)
            : FonadaGetCallList.collect(
                req.campaignName, req.accountName, FonadaGetCallList.parseMax(req.maxRecords), req.recordId);
        res.skipped = String.valueOf(cl.skipped);
        if (cl.error != null) {
            res.message = cl.error;
            return res;
        }
        // Guard key: the Salesforce record, or the dialed number for a direct call.
        String guardKey = direct ? cl.rows[0].get('phone') : (cl.sourceId == null ? null : String.valueOf(cl.sourceId));
        if (cl.rows.isEmpty() && cl.doNotCall > 0 && FonadaGetCallList.isPerson(cl.sourceId)) {
            res.message = cl.source + ' is marked Do Not Call in Salesforce, so it was not called.';
            return res;
        }
        if (cl.rows.isEmpty()) {
            res.message = cl.source + ' has no people with a usable phone number' + cl.skippedText()
                + ', so no campaign was started.';
            return res;
        }

        Datetime now = FonadaGetCallList.now();
        String today = now.format('yyyy-MM-dd', TZ);
        Map<String, String> schedule = FonadaGetCallList.suggestedScheduleMap(now);
        if (String.isNotBlank(req.scheduleDay)) {
            if (!isValidDay(req.scheduleDay.trim())) {
                res.message = 'Schedule day must be a real date like 2026-12-31.';
                return res;
            }
            if (req.scheduleDay.trim() < today) {
                res.message = 'Schedule day ' + req.scheduleDay.trim() + ' is in the past (today is ' + today + ' IST).';
                return res;
            }
            schedule.put('schedule_day', req.scheduleDay.trim());
        }
        if (String.isNotBlank(req.startTime)) {
            if (!TIME_FORMAT.matcher(req.startTime.trim()).matches()) {
                res.message = 'Start time must look like 10:00 (24-hour, IST).';
                return res;
            }
            schedule.put('schedule_start_dtm', pad(req.startTime.trim()));
            if (String.isBlank(req.endTime)) schedule.put('schedule_end_dtm', '23:59');
        }
        if (String.isNotBlank(req.endTime)) {
            if (!TIME_FORMAT.matcher(req.endTime.trim()).matches()) {
                res.message = 'End time must look like 18:00 (24-hour, IST).';
                return res;
            }
            schedule.put('schedule_end_dtm', pad(req.endTime.trim()));
        }
        // A start time already past today means "as soon as possible": start in 2 minutes.
        String soonest = now.addMinutes(2).format('HH:mm', TZ);
        if (schedule.get('schedule_day') == today && schedule.get('schedule_start_dtm') < soonest
                && now.addMinutes(2).format('yyyy-MM-dd', TZ) == today) {
            schedule.put('schedule_start_dtm', soonest);
        }
        if (schedule.get('schedule_end_dtm') <= schedule.get('schedule_start_dtm')) {
            res.message = 'The dial window must end after it starts (start ' + schedule.get('schedule_start_dtm')
                + ', end ' + schedule.get('schedule_end_dtm') + ' IST on ' + schedule.get('schedule_day')
                + '). Ask the user for a later end time or another day.';
            return res;
        }
        res.schedule = schedule.get('schedule_day') + ' ' + schedule.get('schedule_start_dtm')
            + '–' + schedule.get('schedule_end_dtm') + ' IST';

        if (!FonadaLaunchGuard.allowsRepeat(req.allowRepeat)) {
            String repeatMessage = FonadaLaunchGuard.check(guardKey, agent,
                'a Fonada campaign for ' + cl.source + ' with agent ' + agent, 'start_fonada_campaign');
            if (repeatMessage != null) {
                res.message = repeatMessage;
                return res;
            }
        }

        String title = String.isNotBlank(req.campaignTitle)
            ? FonadaSettings.cleanText(req.campaignTitle, TITLE_LENGTH)
            : cl.source.replaceFirst('^(Campaign|Account|Contact|Lead|Phone) ', '') + ' ' + now.format('yyyy-MM-dd HH:mm', TZ);

        List<Object> rows = new List<Object>();
        for (Map<String, String> r : cl.rows) rows.add(r);
        Map<String, Object> args = new Map<String, Object>{
            'name' => title,
            'agent' => agent,
            'csv_rows' => rows,
            'schedule' => schedule,
            'description' => 'Started from Salesforce Agentforce (' + cl.source + ')'
        };

        FonadaMcpClient.ToolResult tr = FonadaMcpClient.callTool('voice_campaigns_create_outbound', args);
        if (!tr.ok) {
            res.message = 'Fonada did not start the campaign: ' + tr.error;
            return res;
        }
        res.success = 'true';
        res.peopleQueued = String.valueOf(cl.rows.size());
        res.fonadaCampaignName = tr.data != null && tr.data.get('name') != null ? String.valueOf(tr.data.get('name')) : title;
        res.fonadaCampaignId = tr.data != null && tr.data.get('id') != null ? String.valueOf(tr.data.get('id')) : null;
        res.message = 'Started Fonada campaign "' + res.fonadaCampaignName + '"'
            + (res.fonadaCampaignId == null ? '' : ' (id ' + res.fonadaCampaignId + ')')
            + ' with agent ' + agent + ' for ' + (cl.rows.size() == 1 ? '1 person' : cl.rows.size() + ' people')
            + ' from ' + cl.source
            + cl.skippedText()
            + ', dialing ' + res.schedule + '. Results are collected automatically.';
        FonadaLaunchGuard.record('Voice', guardKey, cl.source, agent, res.fonadaCampaignId,
            res.fonadaCampaignName, res.schedule, cl.rows.size());
        return res;
    }

    private static String pad(String hhmm) {
        return hhmm.length() == 4 ? '0' + hhmm : hhmm;
    }

    /** YYYY-MM-DD that is a real calendar date (rejects 2026-02-30, 2026-13-01). */
    @TestVisible
    private static Boolean isValidDay(String day) {
        if (!DAY_FORMAT.matcher(day).matches()) return false;
        Integer y = Integer.valueOf(day.substring(0, 4));
        Integer m = Integer.valueOf(day.substring(5, 7));
        Integer d = Integer.valueOf(day.substring(8, 10));
        if (m < 1 || m > 12 || d < 1) return false;
        return d <= Date.daysInMonth(y, m);
    }
}
