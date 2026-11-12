/**
 * Fonada MCP - Agentforce action: find a Salesforce Contact or Lead by name.
 *
 * Read-only. For Agentforce agent users (no CRM access of their own) the reads
 * run in system mode and return only name, account/company, phone, email and
 * Do Not Call; for any other user they run in user mode (sharing + field
 * security). See FonadaSettings. Records marked Do Not Call get no dial number
 * unless an admin allows them in Fonada Settings.
 */
global without sharing class FonadaFindRecord {

    global class Request {
        @InvocableVariable(label='Name' description='Full or partial name of the contact or lead' required=true)
        global String name;
        @InvocableVariable(label='Record type' description='Contact, Lead or Any. Defaults to Any.')
        global String recordType;
    }

    global class Result {
        @InvocableVariable(label='Found' description='true when a matching record was found')
        global String found;
        @InvocableVariable(label='Record type' description='Contact or Lead')
        global String recordType;
        @InvocableVariable(label='Record Id' description='Salesforce record id')
        global String recordId;
        @InvocableVariable(label='Full name' description='Full name of the best match')
        global String fullName;
        @InvocableVariable(label='Company' description='Account name (contact) or company (lead)')
        global String company;
        @InvocableVariable(label='Phone' description='Phone as stored in Salesforce')
        global String phone;
        @InvocableVariable(label='Dial number' description='Phone in Fonada dial format (e.g. 9193XXXXXXXX); empty when the record has no usable number or is marked Do Not Call')
        global String dialNumber;
        @InvocableVariable(label='Email' description='Email address')
        global String email;
        @InvocableVariable(label='Do Not Call' description='true when the record is marked Do Not Call in Salesforce')
        global String doNotCall;
        @InvocableVariable(label='Other matches' description='Other records that also matched the name')
        global String otherMatches;
        @InvocableVariable(label='Message' description='Plain-language summary of the result')
        global String message;
    }

    private static final Integer MAX_MATCHES = 5;
    private static final Integer TEXT_LENGTH = 80;

    @InvocableMethod(label='Fonada: Find Contact or Lead'
        description='Finds a Salesforce contact or lead by name and returns its phone (in Fonada dial format), company and email.'
        category='Fonada MCP')
    global static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();
        for (Request r : requests) results.add(findOne(r));
        return results;
    }

    private static Result findOne(Request req) {
        Result res = new Result();
        res.found = 'false';
        if (!FonadaSettings.crmActionsEnabled()) {
            res.message = FonadaSettings.CRM_DISABLED_MESSAGE;
            return res;
        }
        String name = req == null ? null : req.name;
        if (String.isBlank(name)) {
            res.message = 'No name was given. Ask the user which contact or lead to look up.';
            return res;
        }
        name = name.trim();
        String type = String.isBlank(req.recordType) ? 'any' : req.recordType.trim().toLowerCase();
        Map<String, Object> binds = new Map<String, Object>{
            'pattern' => '%' + FonadaSettings.escapeLike(name) + '%',
            'lim' => MAX_MATCHES
        };
        AccessLevel mode = FonadaSettings.crmAccessLevel();
        Boolean allowDnc = FonadaSettings.includeDoNotCall();

        // DoNotCall is read only where the org has it (and, in user mode, the person can see it).
        Boolean contactDnc = FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'DoNotCall', mode);
        Boolean leadDnc = FonadaSettings.fieldUsable(Schema.Lead.SObjectType, 'DoNotCall', mode);

        List<Match> matches = new List<Match>();
        try {
            if (type != 'lead') {
                for (Contact c : (List<Contact>) Database.queryWithBinds(
                        'SELECT Id, Name, Phone, MobilePhone, Email, Account.Name' + (contactDnc ? ', DoNotCall' : '')
                        + ' FROM Contact WHERE Name LIKE :pattern ORDER BY LastModifiedDate DESC LIMIT :lim',
                        binds, mode)) {
                    matches.add(new Match('Contact', c.Id, c.Name, c.Account?.Name, c.Phone, c.MobilePhone,
                        c.Email, contactDnc && c.get('DoNotCall') == true, allowDnc));
                }
            }
            if (type != 'contact') {
                for (Lead l : (List<Lead>) Database.queryWithBinds(
                        'SELECT Id, Name, Phone, MobilePhone, Email, Company' + (leadDnc ? ', DoNotCall' : '')
                        + ' FROM Lead WHERE Name LIKE :pattern AND IsConverted = false'
                        + ' ORDER BY LastModifiedDate DESC LIMIT :lim', binds, mode)) {
                    matches.add(new Match('Lead', l.Id, l.Name, l.Company, l.Phone, l.MobilePhone,
                        l.Email, leadDnc && l.get('DoNotCall') == true, allowDnc));
                }
            }
        } catch (Exception e) {
            // USER_MODE reads throw when the running person lacks object or field access.
            res.message = 'Could not read Salesforce contacts or leads (check your access to them and their '
                + 'phone and email fields): ' + e.getMessage();
            return res;
        }
        if (matches.isEmpty()) {
            res.message = 'No contact or lead named "' + FonadaSettings.cleanText(name, TEXT_LENGTH)
                + '" was found in Salesforce.';
            return res;
        }

        Match best = matches[0];
        for (Match m : matches) {
            if (m.name != null && m.name.equalsIgnoreCase(name)) { best = m; break; }
        }
        res.found = 'true';
        res.recordType = best.type;
        res.recordId = best.id;
        res.fullName = best.name;
        res.company = best.company;
        res.phone = best.phone;
        res.dialNumber = best.dialNumber;
        res.email = best.email;
        res.doNotCall = String.valueOf(best.doNotCall);

        List<String> others = new List<String>();
        for (Match m : matches) if (m !== best) others.add(m.describe());
        res.otherMatches = String.join(others, '; ');
        String phoneNote = '.';
        if (best.blockedByDnc) {
            phoneNote = '. This record is marked Do Not Call in Salesforce, so it must not be called.';
        } else if (best.dialNumber == null) {
            phoneNote = '. This record has no usable phone number.';
        }
        res.message = 'Found ' + best.describe() + phoneNote
            + (others.isEmpty() ? '' : ' Other matches: ' + res.otherMatches + '.');
        return res;
    }

    private class Match {
        String type, id, name, company, phone, dialNumber, email;
        Boolean doNotCall, blockedByDnc;
        Match(String type, Id id, String name, String company, String phone, String mobile, String email,
              Boolean doNotCall, Boolean allowDnc) {
            this.type = type;
            this.id = id;
            this.name = FonadaSettings.cleanText(name, TEXT_LENGTH);
            this.company = FonadaSettings.cleanText(company, TEXT_LENGTH);
            this.phone = FonadaSettings.cleanText(String.isNotBlank(phone) ? phone : mobile, 40);
            this.email = FonadaSettings.cleanText(email, TEXT_LENGTH);
            this.doNotCall = doNotCall == true;
            this.blockedByDnc = this.doNotCall && !allowDnc;
            this.dialNumber = this.blockedByDnc ? null : FonadaPhone.firstDialNumber(new List<String>{ phone, mobile });
        }
        String describe() {
            return name + ' (' + type + (company == null ? '' : ', ' + company)
                + (phone == null ? ', no phone' : ', ' + phone)
                + (doNotCall ? ', Do Not Call' : '') + ')';
        }
    }
}
