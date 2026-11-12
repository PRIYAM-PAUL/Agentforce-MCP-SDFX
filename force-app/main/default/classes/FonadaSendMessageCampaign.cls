/**
 * Fonada MCP - Agentforce action: send an approved WhatsApp or RCS template to people
 * taken straight from Salesforce, with no CSV upload.
 *
 * Recipients: the members of a Salesforce Campaign, the contacts of an Account, one
 * Contact or Lead (recordId from find_crm_record), or one phone number the user typed.
 * The list is built in Apex by FonadaGetCallList.collect (same rules as voice campaigns:
 * Fonada phone format, duplicates removed, Do Not Call skipped, ambiguous names never
 * picked silently) and sent as "contacts" rows to
 *   - whatsapp_send_campaign (WhatsApp), or
 *   - rcs_run_campaign (RCS; the template name is resolved to its id with rcs_list_bots
 *     and rcs_list_templates).
 * Template variables: nameVariable puts each person's name into that template variable
 * (e.g. BODY_1 for WhatsApp, customer_name for RCS); extraVariables adds the same fixed
 * values to every row. Repeat launches are guarded and logged (FonadaLaunchGuard).
 */
global without sharing class FonadaSendMessageCampaign {

    global class Request {
        @InvocableVariable(label='Channel' description='WhatsApp or RCS' required=true)
        global String channel;
        @InvocableVariable(label='Template name' description='Exact name of the approved WhatsApp or RCS template (an RCS template id also works)')
        global String templateName;
        @InvocableVariable(label='Campaign name' description='Salesforce Campaign whose contact and lead members get the message')
        global String campaignName;
        @InvocableVariable(label='Account name' description='Salesforce Account whose contacts get the message (when no campaign is given)')
        global String accountName;
        @InvocableVariable(label='Record Id' description='Id of the Salesforce Campaign or Account (sourceId from get_crm_call_list), or of one Contact or Lead (recordId from find_crm_record). Takes priority over the names.')
        global String recordId;
        @InvocableVariable(label='Phone number' description='Only for a person who is not in Salesforce: the phone number the user typed. Ignored when a campaign, account or recordId is given.')
        global String phoneNumber;
        @InvocableVariable(label='Person name' description='Name of the person for a direct phone number message')
        global String personName;
        @InvocableVariable(label='Name variable' description='Optional template variable that gets each person\'s name, e.g. BODY_1 (WhatsApp) or customer_name (RCS)')
        global String nameVariable;
        @InvocableVariable(label='Extra variables' description='Optional fixed template values for everyone, as KEY=value; KEY2=value')
        global String extraVariables;
        @InvocableVariable(label='Fonada campaign title' description='Optional name for the Fonada campaign. Defaults to the Salesforce source plus channel, date and time.')
        global String campaignTitle;
        @InvocableVariable(label='Max records' description='Maximum number of people (default 200, max 1000)')
        global String maxRecords;
        @InvocableVariable(label='WhatsApp account id' description='Optional WhatsApp Business Account id, only when the user has several WhatsApp numbers')
        global String whatsappAccountId;
        @InvocableVariable(label='RCS bot name' description='Optional RCS bot name, only when several RCS bots have a template with the same name')
        global String rcsBotName;
        @InvocableVariable(label='Allow repeat' description='true only when the user explicitly confirmed sending the same template to the same people again within a few minutes')
        global String allowRepeat;
    }

    global class Result {
        @InvocableVariable(label='Success' description='true when Fonada accepted and launched the campaign')
        global String success;
        @InvocableVariable(label='Channel' description='WhatsApp or RCS')
        global String channel;
        @InvocableVariable(label='Fonada campaign name' description='Name of the created Fonada campaign')
        global String fonadaCampaignName;
        @InvocableVariable(label='Fonada campaign id' description='Id of the created Fonada campaign')
        global String fonadaCampaignId;
        @InvocableVariable(label='People queued' description='Number of people sent to Fonada')
        global String peopleQueued;
        @InvocableVariable(label='Skipped' description='People skipped (no phone, duplicate, Do Not Call or over the limit)')
        global String skipped;
        @InvocableVariable(label='Message' description='Plain-language result, the list of RCS templates, or the exact error from Fonada')
        global String message;
    }

    public static final String WHATSAPP = 'WhatsApp';
    public static final String RCS = 'RCS';
    private static final String TZ = 'Asia/Kolkata';
    private static final Pattern UUID_FORMAT =
        Pattern.compile('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
    private static final Pattern VARIABLE_FORMAT = Pattern.compile('^[A-Za-z][A-Za-z0-9_]{0,39}$');
    private static final Set<String> RESERVED_KEYS = new Set<String>{ 'phone', 'name' };
    private static final Integer MAX_BOTS = 5;
    private static final Integer MAX_LISTED = 15;
    private static final Integer MAX_EXTRAS = 10;

    @InvocableMethod(label='Fonada: Send Message Campaign'
        description='Sends an approved WhatsApp or RCS template to the people in a Salesforce Campaign or Account, or to one Contact, Lead or phone number. Builds the recipient list from Salesforce and launches the Fonada campaign in one step.'
        category='Fonada MCP' callout=true)
    global static List<Result> send(List<Request> requests) {
        List<Result> results = new List<Result>();
        FonadaLaunchGuard.reset();
        for (Request r : requests) results.add(sendOne(r));
        FonadaLaunchGuard.flush();   // after all callouts: DML before a callout is not allowed
        return results;
    }

    private static Result sendOne(Request req) {
        Result res = new Result();
        res.success = 'false';
        res.peopleQueued = '0';
        res.skipped = '0';
        String channel = req == null ? null : normalizeChannel(req.channel);
        if (channel == null) {
            res.message = 'Ask the user whether to send the message by WhatsApp or RCS.';
            return res;
        }
        res.channel = channel;
        String template = FonadaSettings.cleanText(req.templateName, 120);
        if (String.isBlank(template) && channel == WHATSAPP) {
            res.message = 'Ask the user which approved WhatsApp template to send (use whatsapp_list_templates).';
            return res;
        }

        String nameVar = String.isBlank(req.nameVariable) ? null : req.nameVariable.trim();
        if (nameVar != null && (!VARIABLE_FORMAT.matcher(nameVar).matches() || RESERVED_KEYS.contains(nameVar.toLowerCase()))) {
            res.message = 'Name variable "' + FonadaSettings.cleanText(nameVar, 40) + '" is not a valid template '
                + 'variable name (letters, digits and _, e.g. BODY_1 or customer_name).';
            return res;
        }
        Map<String, String> extras = new Map<String, String>();
        String extrasError = parseExtras(req.extraVariables, extras);
        if (extrasError != null) {
            res.message = extrasError;
            return res;
        }

        // RCS needs the template id; resolve (or list the templates) before reading Salesforce.
        String rcsTemplateId;
        if (channel == RCS) {
            RcsTemplate rt = resolveRcsTemplate(template, req.rcsBotName);
            if (rt.error != null) {
                res.message = rt.error;
                return res;
            }
            rcsTemplateId = rt.id;
            template = rt.name;
        }

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
        if (cl.rows.isEmpty() && cl.doNotCall > 0 && FonadaGetCallList.isPerson(cl.sourceId)) {
            res.message = cl.source + ' is marked Do Not Call in Salesforce, so no message was sent.';
            return res;
        }
        if (cl.rows.isEmpty()) {
            res.message = cl.source + ' has no people with a usable phone number' + cl.skippedText()
                + ', so no message was sent.';
            return res;
        }

        String guardKey = direct ? cl.rows[0].get('phone') : (cl.sourceId == null ? null : String.valueOf(cl.sourceId));
        String agentKey = channel + ' template ' + template;
        if (!FonadaLaunchGuard.allowsRepeat(req.allowRepeat)) {
            String repeatMessage = FonadaLaunchGuard.check(guardKey, agentKey,
                'a ' + channel + ' campaign with template ' + template + ' for ' + cl.source, 'send_message_campaign');
            if (repeatMessage != null) {
                res.message = repeatMessage;
                return res;
            }
        }

        Datetime now = FonadaGetCallList.now();
        String title = String.isNotBlank(req.campaignTitle)
            ? FonadaSettings.cleanText(req.campaignTitle, 120)
            : cl.source.replaceFirst('^(Campaign|Account|Contact|Lead|Phone) ', '') + ' ' + channel + ' '
                + now.format('yyyy-MM-dd HH:mm', TZ);
        String description = 'Sent from Salesforce Agentforce (' + cl.source + ')';

        List<Object> contacts = new List<Object>();
        for (Map<String, String> row : cl.rows) {
            Map<String, Object> c = new Map<String, Object>{
                'phone' => row.get('phone').removeStart('+'),   // both channels expect digits only
                'name' => row.get('name')
            };
            if (nameVar != null) c.put(nameVar, row.get('name'));
            c.putAll(extras);
            contacts.add(c);
        }

        String toolName;
        Map<String, Object> args;
        if (channel == WHATSAPP) {
            toolName = 'whatsapp_send_campaign';
            args = new Map<String, Object>{
                'campaign_name' => title,
                'template_name' => template,
                'contacts' => contacts,
                'description' => description
            };
            if (String.isNotBlank(req.whatsappAccountId)) {
                args.put('account_id', FonadaSettings.cleanText(req.whatsappAccountId, 64));
            }
        } else {
            toolName = 'rcs_run_campaign';
            args = new Map<String, Object>{
                'name' => title,
                'template_id' => rcsTemplateId,
                'contacts' => contacts,
                'country_code' => FonadaSettings.countryCode(),
                'description' => description
            };
            Map<String, Object> mapping = new Map<String, Object>();
            if (nameVar != null) mapping.put(nameVar, nameVar);
            for (String k : extras.keySet()) mapping.put(k, k);
            if (!mapping.isEmpty()) args.put('parameter_mapping', mapping);
        }

        FonadaMcpClient.ToolResult tr = FonadaMcpClient.callTool(toolName, args);
        if (!tr.ok) {
            res.message = 'Fonada did not send the ' + channel + ' campaign: ' + tr.error;
            return res;
        }
        Map<String, Object> data = unwrap(tr.data);
        res.fonadaCampaignId = firstText(data, new List<String>{ 'id', 'campaign_id' });
        res.fonadaCampaignName = firstText(data, new List<String>{ 'name', 'campaign_name' });
        if (res.fonadaCampaignName == null) res.fonadaCampaignName = title;

        if (data != null && data.get('launched') == false) {
            String launchError = firstText(data, new List<String>{ 'launch_error', 'error' });
            res.message = 'Fonada saved the ' + channel + ' campaign "' + res.fonadaCampaignName + '"'
                + (res.fonadaCampaignId == null ? '' : ' (id ' + res.fonadaCampaignId + ')')
                + ' as a draft but did not send it' + (launchError == null ? '' : ': ' + launchError)
                + '. Fix the problem in Fonada, then launch the draft from the Fonada dashboard.';
            return res;
        }

        res.success = 'true';
        res.peopleQueued = String.valueOf(cl.rows.size());
        res.message = 'Sent ' + channel + ' template "' + template + '" to '
            + (cl.rows.size() == 1 ? '1 person' : cl.rows.size() + ' people') + ' from ' + cl.source
            + cl.skippedText() + ' as Fonada campaign "' + res.fonadaCampaignName + '"'
            + (res.fonadaCampaignId == null ? '' : ' (id ' + res.fonadaCampaignId + ')') + '.';
        FonadaLaunchGuard.record(channel, guardKey, cl.source, agentKey, res.fonadaCampaignId,
            res.fonadaCampaignName, null, cl.rows.size());
        return res;
    }

    @TestVisible
    private static String normalizeChannel(String raw) {
        if (String.isBlank(raw)) return null;
        String c = raw.trim().toLowerCase().replaceAll('[^a-z]', '');
        if (c == 'whatsapp' || c == 'wa') return WHATSAPP;
        if (c == 'rcs') return RCS;
        return null;
    }

    /** Parses "KEY=value; KEY2=value" into extras; returns an error message or null. */
    @TestVisible
    private static String parseExtras(String raw, Map<String, String> extras) {
        if (String.isBlank(raw)) return null;
        for (String part : raw.split(';')) {
            if (String.isBlank(part)) continue;
            Integer eq = part.indexOf('=');
            String key = eq < 0 ? part.trim() : part.substring(0, eq).trim();
            if (eq < 0 || !VARIABLE_FORMAT.matcher(key).matches() || RESERVED_KEYS.contains(key.toLowerCase())) {
                return 'Extra variables must look like KEY=value; KEY2=value (keys: letters, digits and _). '
                    + 'Problem with "' + FonadaSettings.cleanText(part, 40) + '".';
            }
            extras.put(key, FonadaSettings.cleanText(part.substring(eq + 1).trim(), 200));
            if (extras.size() > MAX_EXTRAS) return 'At most ' + MAX_EXTRAS + ' extra variables are allowed.';
        }
        return null;
    }

    private class RcsTemplate {
        String id, name, error;
    }

    /**
     * Finds the RCS template id by name across the user's RCS bots (at most MAX_BOTS).
     * A UUID is used as-is. With no or an unknown name, error lists the available templates.
     */
    private static RcsTemplate resolveRcsTemplate(String name, String botName) {
        RcsTemplate rt = new RcsTemplate();
        if (String.isNotBlank(name) && UUID_FORMAT.matcher(name).matches()) {
            rt.id = name;
            rt.name = name;
            return rt;
        }
        FonadaMcpClient.ToolResult bots = FonadaMcpClient.callTool('rcs_list_bots', new Map<String, Object>());
        if (!bots.ok) {
            rt.error = 'Could not list your RCS bots in Fonada: ' + bots.error;
            return rt;
        }
        List<Map<String, Object>> botList = new List<Map<String, Object>>();
        for (Object o : asList(bots.text)) {
            if (!(o instanceof Map<String, Object>)) continue;
            Map<String, Object> b = (Map<String, Object>) o;
            if (String.isNotBlank(botName) && !botName.trim().equalsIgnoreCase(String.valueOf(b.get('bot_name')))) continue;
            if (b.get('id') != null) botList.add(b);
        }
        if (botList.isEmpty()) {
            rt.error = String.isNotBlank(botName)
                ? 'No RCS bot named "' + FonadaSettings.cleanText(botName, 80) + '" was found in Fonada.'
                : 'No RCS bot was found in this Fonada account. Set up an RCS bot and template in Fonada first.';
            return rt;
        }

        List<String> available = new List<String>();
        List<String> matchIds = new List<String>();
        List<String> matchBots = new List<String>();
        String matchName;
        List<String> problems = new List<String>();
        for (Integer i = 0; i < Math.min(botList.size(), MAX_BOTS); i++) {
            Map<String, Object> b = botList[i];
            String bName = FonadaSettings.cleanText(String.valueOf(b.get('bot_name')), 80);
            FonadaMcpClient.ToolResult t = FonadaMcpClient.callTool('rcs_list_templates',
                new Map<String, Object>{ 'bot_id' => String.valueOf(b.get('id')) });
            if (!t.ok) {
                problems.add(bName + ': ' + FonadaSettings.cleanText(t.error, 150));
                continue;
            }
            for (Object o : asList(t.text)) {
                if (!(o instanceof Map<String, Object>)) continue;
                Map<String, Object> tpl = (Map<String, Object>) o;
                // Prod returns the name as "template_name"; "name" is kept as a fallback.
                String tName = FonadaSettings.cleanText(
                    firstText(tpl, new List<String>{ 'template_name', 'name' }), 80);
                if (tpl.get('id') == null || tName == null) continue;
                if (available.size() < MAX_LISTED) {
                    available.add(tName + (tpl.get('status') == null ? '' : ' [' + tpl.get('status') + ']')
                        + ' (bot ' + bName + ')');
                }
                if (String.isNotBlank(name) && tName.equalsIgnoreCase(name.trim())) {
                    matchIds.add(String.valueOf(tpl.get('id')));
                    matchBots.add(bName);
                    matchName = tName;
                }
            }
        }
        if (matchIds.size() == 1) {
            rt.id = matchIds[0];
            rt.name = matchName;
            return rt;
        }
        if (matchIds.size() > 1) {
            rt.error = 'Several RCS bots have a template named "' + matchName + '": ' + String.join(matchBots, ', ')
                + '. Ask the user which bot, then call again with rcsBotName.';
            return rt;
        }
        String listText = available.isEmpty() ? 'No RCS templates were found'
            : 'Available RCS templates: ' + String.join(available, '; ');
        rt.error = (String.isBlank(name) ? 'Ask the user which RCS template to send. '
                : 'No RCS template named "' + name + '" was found. ')
            + listText + (problems.isEmpty() ? '' : ' (could not read: ' + String.join(problems, '; ') + ')') + '.';
        return rt;
    }

    /** Parses a tool's text result as a list: a JSON array, or an object holding one. */
    private static List<Object> asList(String text) {
        if (String.isBlank(text)) return new List<Object>();
        try {
            Object parsed = JSON.deserializeUntyped(text);
            if (parsed instanceof List<Object>) return (List<Object>) parsed;
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) parsed;
                for (String k : new List<String>{ 'result', 'bots', 'templates', 'data', 'items' }) {
                    if (m.get(k) instanceof List<Object>) return (List<Object>) m.get(k);
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.FINEST, 'FonadaMCP: tool result is not a JSON list');
        }
        return new List<Object>();
    }

    /** The campaign object, also when wrapped as {"result": {...}} or {"campaign": {...}}. */
    private static Map<String, Object> unwrap(Map<String, Object> data) {
        if (data == null) return null;
        for (String k : new List<String>{ 'result', 'campaign', 'data' }) {
            if (data.get(k) instanceof Map<String, Object>) return (Map<String, Object>) data.get(k);
        }
        return data;
    }

    private static String firstText(Map<String, Object> data, List<String> keys) {
        if (data == null) return null;
        for (String k : keys) {
            if (data.get(k) != null && !(data.get(k) instanceof Map<String, Object>)) {
                return FonadaSettings.cleanText(String.valueOf(data.get(k)), 255);
            }
        }
        return null;
    }
}
