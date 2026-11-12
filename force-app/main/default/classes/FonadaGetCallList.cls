/**
 * Fonada MCP - Agentforce action: build a Fonada call list from Salesforce.
 *
 * Source is either a Salesforce Campaign (its contact and lead members) or an
 * Account (its contacts). Returns the rows ready for the Fonada tool
 * voice_campaigns_create_outbound (csv_rows) plus a suggested dial window.
 *
 * Read-only. For Agentforce agent users (no CRM access of their own) the reads
 * run in system mode and return only names and phones; for any other user they
 * run in user mode (sharing + field security). See FonadaSettings.
 * Do Not Call records are skipped unless an admin allows them in Fonada Settings.
 */
global without sharing class FonadaGetCallList {

    global class Request {
        @InvocableVariable(label='Campaign name' description='Name of a Salesforce Campaign whose contact and lead members should be called')
        global String campaignName;
        @InvocableVariable(label='Account name' description='Name of a Salesforce Account whose contacts should be called')
        global String accountName;
        @InvocableVariable(label='Max records' description='Maximum number of people to include (default 200, max 1000)')
        global String maxRecords;
        @InvocableVariable(label='Record Id' description='Optional Id of the Salesforce Campaign or Account (from an earlier result), or of one Contact or Lead. Takes priority over the names.')
        global String recordId;
    }

    global class Result {
        @InvocableVariable(label='Source' description='The Salesforce campaign or account the list was built from')
        global String source;
        @InvocableVariable(label='Source Id' description='Id of the Salesforce Campaign or Account used. Pass it as recordId to start_fonada_campaign.')
        global String sourceId;
        @InvocableVariable(label='Count' description='Number of people with a usable phone number')
        global String count;
        @InvocableVariable(label='Skipped' description='Number of people skipped (no usable phone, duplicate, Do Not Call or over the limit)')
        global String skipped;
        @InvocableVariable(label='Preview' description='First few names and numbers, to show the user before launching')
        global String preview;
        @InvocableVariable(label='Leads JSON' description='JSON array of {"phone","name"} rows. Pass it as csv_rows to voice_campaigns_create_outbound.')
        global String leadsJson;
        @InvocableVariable(label='Suggested schedule' description='JSON dial window in IST starting now. Pass it as schedule to voice_campaigns_create_outbound unless the user gave another window.')
        global String suggestedSchedule;
        @InvocableVariable(label='Message' description='Plain-language summary of the result')
        global String message;
    }

    private static final Integer DEFAULT_MAX = 200;
    private static final Integer HARD_MAX = 1000;
    private static final Integer PREVIEW_SIZE = 5;
    private static final Integer MAX_CANDIDATES = 5;
    private static final Integer NAME_LENGTH = 80;
    @TestVisible private static Datetime nowOverride;

    @InvocableMethod(label='Fonada: Get Call List'
        description='Builds a call list (names and phones in Fonada format) from a Salesforce Campaign or Account, ready for a Fonada outbound campaign.'
        category='Fonada MCP')
    global static List<Result> build(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) results.add(buildOne(r));
        return results;
    }

    /** Call list built from Salesforce; shared with FonadaStartCampaign. */
    public class CallList {
        public String source;
        public Id sourceId;
        public String error;
        public Integer skipped = 0;
        public Integer doNotCall = 0;
        public Integer notIncluded = 0;
        public List<Map<String, String>> rows = new List<Map<String, String>>();
        public List<String> preview = new List<String>();
        public String previewText() {
            return String.join(preview, '; ') + (rows.size() > PREVIEW_SIZE ? '; …' : '');
        }
        /** e.g. " (3 skipped: 1 Do Not Call; no phone, duplicate or over the limit; 40 more not read)" */
        public String skippedText() {
            List<String> parts = new List<String>();
            if (skipped > 0) {
                parts.add(skipped + ' skipped' + (doNotCall > 0 ? ' (' + doNotCall + ' Do Not Call)' : '')
                    + ': no usable phone, duplicate, Do Not Call or over the limit');
            }
            if (notIncluded > 0) parts.add(notIncluded + ' more members were not included (list limit)');
            return parts.isEmpty() ? '' : ' (' + String.join(parts, '; ') + ')';
        }
    }

    private static Result buildOne(Request req) {
        Result res = new Result();
        res.count = '0';
        res.skipped = '0';
        res.suggestedSchedule = JSON.serialize(suggestedScheduleMap(now()));
        CallList cl = collect(req == null ? null : req.campaignName,
                              req == null ? null : req.accountName,
                              parseMax(req == null ? null : req.maxRecords),
                              req == null ? null : req.recordId);
        if (cl.error != null) {
            res.message = cl.error;
            return res;
        }
        res.source = cl.source;
        res.sourceId = cl.sourceId;
        res.count = String.valueOf(cl.rows.size());
        res.skipped = String.valueOf(cl.skipped);
        res.leadsJson = JSON.serialize(cl.rows);
        res.preview = cl.previewText();
        res.message = cl.rows.isEmpty()
            ? cl.source + ' has no people with a usable phone number' + cl.skippedText() + '.'
            : cl.source + ': ' + cl.rows.size() + ' people ready to call' + cl.skippedText()
                + '. First: ' + res.preview;
        return res;
    }

    /** Backwards-compatible overload (by name only). */
    public static CallList collect(String campaign, String account, Integer max) {
        return collect(campaign, account, max, null);
    }

    /**
     * Reads the Campaign members or Account contacts and returns de-duplicated dial rows.
     * recordId (Campaign or Account Id, or a Contact or Lead Id for a single call) wins over the names. A name is matched exactly
     * first; a partial name must match exactly one record, otherwise the candidates are
     * returned as an error so the user can choose (nothing is ever picked silently).
     */
    public static CallList collect(String campaign, String account, Integer max, String recordId) {
        CallList cl = new CallList();
        if (!FonadaSettings.crmActionsEnabled()) {
            cl.error = FonadaSettings.CRM_DISABLED_MESSAGE;
            return cl;
        }
        if (String.isBlank(campaign) && String.isBlank(account) && String.isBlank(recordId)) {
            cl.error = 'Ask the user which Salesforce Campaign or Account to build the call list from.';
            return cl;
        }
        if (max == null || max < 1) max = DEFAULT_MAX;
        max = Math.min(max, HARD_MAX);
        Integer queryLimit = max * 2;
        Boolean skipDnc = !FonadaSettings.includeDoNotCall();
        AccessLevel mode = FonadaSettings.crmAccessLevel();
        List<Person> people = new List<Person>();

        try {
            SObject src = resolveSource(campaign, account, recordId, mode, cl);
            if (src == null) return cl;
            cl.sourceId = src.Id;
            String srcName = FonadaSettings.cleanText((String) src.get('Name'), NAME_LENGTH);
            Integer total;
            Map<String, Object> binds = new Map<String, Object>{ 'srcId' => src.Id, 'lim' => queryLimit };

            // DoNotCall is read only where the org has it (and, in user mode, the person can see it).
            Boolean contactDnc = FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'DoNotCall', mode);
            Boolean leadDnc = FonadaSettings.fieldUsable(Schema.Lead.SObjectType, 'DoNotCall', mode);

            if (src.getSObjectType() == Schema.Campaign.SObjectType) {
                cl.source = 'Campaign ' + srcName;
                String fields = 'ContactId, LeadId, Contact.Name, Contact.Phone, Contact.MobilePhone,'
                    + ' Lead.Name, Lead.Phone, Lead.MobilePhone'
                    + (contactDnc ? ', Contact.DoNotCall' : '') + (leadDnc ? ', Lead.DoNotCall' : '');
                for (CampaignMember m : (List<CampaignMember>) Database.queryWithBinds(
                        'SELECT ' + fields + ' FROM CampaignMember WHERE CampaignId = :srcId LIMIT :lim', binds, mode)) {
                    if (m.ContactId != null) {
                        people.add(new Person(m.Contact.Name, m.Contact.Phone, m.Contact.MobilePhone,
                            contactDnc && m.Contact.get('DoNotCall') == true));
                    } else if (m.LeadId != null) {
                        people.add(new Person(m.Lead.Name, m.Lead.Phone, m.Lead.MobilePhone,
                            leadDnc && m.Lead.get('DoNotCall') == true));
                    }
                }
                if (people.size() >= queryLimit) {
                    total = Database.countQueryWithBinds(
                        'SELECT COUNT() FROM CampaignMember WHERE CampaignId = :srcId', binds, mode);
                }
            } else if (src.getSObjectType() == Schema.Contact.SObjectType
                    || src.getSObjectType() == Schema.Lead.SObjectType) {
                // One person (single call): the Contact or Lead returned by find_crm_record.
                Boolean isContact = src.getSObjectType() == Schema.Contact.SObjectType;
                Boolean dnc = isContact ? contactDnc : leadDnc;
                String objectName = isContact ? 'Contact' : 'Lead';
                cl.source = objectName + ' ' + srcName;
                for (SObject p : Database.queryWithBinds(
                        'SELECT Name, Phone, MobilePhone' + (dnc ? ', DoNotCall' : '')
                        + ' FROM ' + objectName + ' WHERE Id = :srcId LIMIT 1', binds, mode)) {
                    people.add(new Person((String) p.get('Name'), (String) p.get('Phone'),
                        (String) p.get('MobilePhone'), dnc && p.get('DoNotCall') == true));
                }
            } else {
                cl.source = 'Account ' + srcName;
                for (Contact c : (List<Contact>) Database.queryWithBinds(
                        'SELECT Name, Phone, MobilePhone' + (contactDnc ? ', DoNotCall' : '')
                        + ' FROM Contact WHERE AccountId = :srcId LIMIT :lim', binds, mode)) {
                    people.add(new Person(c.Name, c.Phone, c.MobilePhone, contactDnc && c.get('DoNotCall') == true));
                }
                if (people.size() >= queryLimit) {
                    total = Database.countQueryWithBinds(
                        'SELECT COUNT() FROM Contact WHERE AccountId = :srcId', binds, mode);
                }
            }
            if (total != null && total > people.size()) cl.notIncluded = total - people.size();
        } catch (Exception e) {
            // USER_MODE reads throw (QueryException / NoAccessException) when the running
            // person lacks object or field access; report it instead of failing the action.
            cl.error = 'Could not read the Salesforce records for the call list (check your access to Campaigns, '
                + 'Accounts, Contacts and Leads and their phone fields): ' + e.getMessage();
            return cl;
        }

        Set<String> seen = new Set<String>();
        for (Person p : people) {
            if (skipDnc && p.doNotCall) {
                cl.skipped++;
                cl.doNotCall++;
                continue;
            }
            if (p.dialNumber == null || seen.contains(p.dialNumber) || cl.rows.size() >= max) {
                cl.skipped++;
                continue;
            }
            seen.add(p.dialNumber);
            cl.rows.add(new Map<String, String>{ 'phone' => p.dialNumber, 'name' => p.name });
            if (cl.preview.size() < PREVIEW_SIZE) cl.preview.add(p.name + ' ' + p.dialNumber);
        }
        return cl;
    }

    /**
     * One person who is not in Salesforce: a phone number the user typed. No CRM data is read,
     * so this works even when the CRM actions are turned off.
     */
    public static CallList directCall(String phone, String personName) {
        CallList cl = new CallList();
        String typed = FonadaSettings.cleanText(phone, 40);
        String dial = FonadaPhone.toDialNumber(typed);
        if (dial == null || dial.length() > 18) {
            cl.error = '"' + typed + '" is not a usable phone number. Ask the user for the full number.';
            return cl;
        }
        String name = String.isBlank(personName) ? dial : FonadaSettings.cleanText(personName, NAME_LENGTH);
        cl.source = 'Phone ' + dial;
        cl.rows.add(new Map<String, String>{ 'phone' => dial, 'name' => name });
        return cl;
    }

    /** True for a Contact or Lead Id (a single-person list). */
    public static Boolean isPerson(Id recordId) {
        return recordId != null && (recordId.getSObjectType() == Schema.Contact.SObjectType
            || recordId.getSObjectType() == Schema.Lead.SObjectType);
    }

    /** Finds the Campaign or Account; sets cl.error and returns null when not found or ambiguous. */
    private static SObject resolveSource(String campaign, String account, String recordId,
                                         AccessLevel mode, CallList cl) {
        if (String.isNotBlank(recordId)) {
            Id rid;
            try {
                rid = Id.valueOf(recordId.trim());
            } catch (Exception e) {
                cl.error = '"' + FonadaSettings.cleanText(recordId, 40) + '" is not a valid Salesforce record Id.';
                return null;
            }
            String objectName;
            if (rid.getSObjectType() == Schema.Campaign.SObjectType) objectName = 'Campaign';
            else if (rid.getSObjectType() == Schema.Account.SObjectType) objectName = 'Account';
            else if (rid.getSObjectType() == Schema.Contact.SObjectType) objectName = 'Contact';
            else if (rid.getSObjectType() == Schema.Lead.SObjectType) objectName = 'Lead';
            else {
                cl.error = 'The record Id must belong to a Salesforce Campaign, Account, Contact or Lead.';
                return null;
            }
            List<SObject> rows = Database.queryWithBinds(
                'SELECT Id, Name FROM ' + objectName + ' WHERE Id = :rid LIMIT 1',
                new Map<String, Object>{ 'rid' => rid }, mode);
            if (rows.isEmpty()) {
                cl.error = 'No Salesforce ' + objectName + ' with Id ' + rid + ' was found.';
                return null;
            }
            return rows[0];
        }
        Boolean isCampaign = String.isNotBlank(campaign);
        String objectName = isCampaign ? 'Campaign' : 'Account';
        String name = (isCampaign ? campaign : account).trim();
        Map<String, Object> binds = new Map<String, Object>{
            'exact' => name,
            'pattern' => '%' + FonadaSettings.escapeLike(name) + '%',
            'lim' => MAX_CANDIDATES + 1
        };
        List<SObject> matches = Database.queryWithBinds(
            'SELECT Id, Name FROM ' + objectName + ' WHERE Name = :exact ORDER BY LastModifiedDate DESC LIMIT :lim',
            binds, mode);
        if (matches.isEmpty()) {
            matches = Database.queryWithBinds(
                'SELECT Id, Name FROM ' + objectName + ' WHERE Name LIKE :pattern ORDER BY LastModifiedDate DESC LIMIT :lim',
                binds, mode);
        }
        if (matches.isEmpty()) {
            cl.error = 'No Salesforce ' + objectName + ' named "' + FonadaSettings.cleanText(name, NAME_LENGTH) + '" was found.';
            return null;
        }
        if (matches.size() > 1) {
            List<String> names = new List<String>();
            for (Integer i = 0; i < Math.min(matches.size(), MAX_CANDIDATES); i++) {
                names.add(FonadaSettings.cleanText((String) matches[i].get('Name'), NAME_LENGTH)
                    + ' (Id ' + matches[i].Id + ')');
            }
            cl.error = 'Several Salesforce ' + objectName + 's match "' + FonadaSettings.cleanText(name, NAME_LENGTH)
                + '": ' + String.join(names, '; ') + (matches.size() > MAX_CANDIDATES ? '; …' : '')
                + '. Ask the user which one, then call again with its exact name or its Id as recordId.';
            return null;
        }
        return matches[0];
    }

    public static Datetime now() {
        return nowOverride != null ? nowOverride : System.now();
    }

    @TestVisible
    public static Integer parseMax(String raw) {
        Integer max = DEFAULT_MAX;
        if (String.isNotBlank(raw) && raw.trim().isNumeric() && raw.trim().length() <= 6) {
            max = Integer.valueOf(raw.trim());
        }
        if (max < 1) max = DEFAULT_MAX;
        return Math.min(max, HARD_MAX);
    }

    /** Dial window in IST from ~now for up to 3 hours, never past midnight. */
    public static Map<String, String> suggestedScheduleMap(Datetime now) {
        String tz = 'Asia/Kolkata';
        Datetime start = now.addMinutes(2);
        Datetime finish = now.addHours(3);
        String day = start.format('yyyy-MM-dd', tz);
        String endTime = finish.format('yyyy-MM-dd', tz) == day ? finish.format('HH:mm', tz) : '23:59';
        return new Map<String, String>{
            'schedule_day' => day,
            'schedule_start_dtm' => start.format('HH:mm', tz),
            'schedule_end_dtm' => endTime
        };
    }

    @TestVisible
    private static String suggestedSchedule(Datetime now) {
        return JSON.serialize(suggestedScheduleMap(now));
    }

    private class Person {
        String name, dialNumber;
        Boolean doNotCall;
        Person(String name, String phone, String mobile, Boolean doNotCall) {
            this.name = FonadaSettings.cleanText(name, NAME_LENGTH);
            this.dialNumber = FonadaPhone.firstDialNumber(new List<String>{ phone, mobile });
            this.doNotCall = doNotCall == true;
        }
    }
}
