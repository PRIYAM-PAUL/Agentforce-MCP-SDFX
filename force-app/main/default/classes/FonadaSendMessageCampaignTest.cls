@IsTest
private class FonadaSendMessageCampaignTest {

    /** Answers like the Fonada MCP server, by JSON-RPC method and tool name. */
    private class FonadaServer implements HttpCalloutMock {
        Map<String, String> toolText = new Map<String, String>();
        Map<String, Boolean> toolError = new Map<String, Boolean>();
        List<String> tools = new List<String>();
        Map<String, Map<String, Object>> argsByTool = new Map<String, Map<String, Object>>();
        public HttpResponse respond(HttpRequest req) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(req.getBody());
            String method = String.valueOf(body.get('method'));
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            if (method == 'initialize') {
                res.setBody('{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-06-18","capabilities":{}}}');
                return res;
            }
            if (method == 'notifications/initialized') {
                res.setStatusCode(202);
                res.setBody('');
                return res;
            }
            Map<String, Object> params = (Map<String, Object>) body.get('params');
            String tool = String.valueOf(params.get('name'));
            tools.add(tool);
            argsByTool.put(tool, (Map<String, Object>) params.get('arguments'));
            String text = toolText.containsKey(tool) ? toolText.get(tool) : '{}';
            Boolean isError = toolError.get(tool) == true;
            res.setBody('event: message\ndata: ' + JSON.serialize(new Map<String, Object>{
                'jsonrpc' => '2.0', 'id' => 1,
                'result' => new Map<String, Object>{
                    'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'text', 'text' => text } },
                    'isError' => isError
                }
            }) + '\n\n');
            return res;
        }
    }

    private static final String TPL_ID = '11111111-2222-3333-4444-555555555555';

    private static FonadaServer rcsServer() {
        FonadaServer s = new FonadaServer();
        s.toolText.put('rcs_list_bots', '[{"id":"bot-1","bot_name":"Travel-helper"},{"id":"bot-2","bot_name":"Promo"}]');
        s.toolText.put('rcs_list_templates', '[{"id":"' + TPL_ID + '","user_id":null,"bot_id":null,"template_name":"diwali_offer","template_code":"diwali_offer_1","template_type":"rich_card","status":"active"}]');
        s.toolText.put('rcs_run_campaign', '{"campaign_id":"rcs-77","status":"running"}');
        return s;
    }

    @TestSetup
    static void data() {
        Account acc = new Account(Name = 'Msg Test Bank');
        insert acc;
        insert new List<Contact>{
            new Contact(FirstName = 'Asha', LastName = 'One', AccountId = acc.Id, Phone = '9300000001'),
            new Contact(FirstName = 'Ben', LastName = 'Two', AccountId = acc.Id, Phone = '+91 93000 00002'),
            new Contact(FirstName = 'No', LastName = 'Number', AccountId = acc.Id)
        };
        Campaign c = new Campaign(Name = 'Msg Diwali Push', IsActive = true);
        insert c;
        insert new CampaignMember(CampaignId = c.Id, ContactId = [SELECT Id FROM Contact WHERE LastName = 'One'].Id);
        Lead l = new Lead(FirstName = 'Lia', LastName = 'Lead', Company = 'Lead Co', MobilePhone = '9300000077');
        insert l;
        insert new CampaignMember(CampaignId = c.Id, LeadId = l.Id);
    }

    private static FonadaSendMessageCampaign.Request req(String channel, String template) {
        FonadaSendMessageCampaign.Request r = new FonadaSendMessageCampaign.Request();
        r.channel = channel;
        r.templateName = template;
        return r;
    }

    private static FonadaSendMessageCampaign.Result run(FonadaSendMessageCampaign.Request r) {
        return FonadaSendMessageCampaign.send(new List<FonadaSendMessageCampaign.Request>{ r })[0];
    }

    @IsTest
    static void whatsappCampaignFromSalesforceCampaign() {
        FonadaServer s = new FonadaServer();
        s.toolText.put('whatsapp_send_campaign', '{"id":"wa-1","name":"Diwali WA","status":"running","launched":true}');
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('whatsapp', 'diwali_offer');
        r.campaignName = 'Msg Diwali Push';
        r.nameVariable = 'BODY_1';
        r.extraVariables = 'BODY_2=DIWALI20; BODY_3 = 31 Oct';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();

        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('WhatsApp', res.channel);
        Assert.areEqual('wa-1', res.fonadaCampaignId);
        Assert.areEqual('2', res.peopleQueued);
        Assert.isTrue(res.message.contains('2 people from Campaign Msg Diwali Push'), res.message);

        Map<String, Object> args = s.argsByTool.get('whatsapp_send_campaign');
        Assert.areEqual('diwali_offer', args.get('template_name'));
        Assert.isNull(args.get('parameter_mapping'), 'WhatsApp rows carry the variables directly');
        List<Object> contacts = (List<Object>) args.get('contacts');
        Assert.areEqual(2, contacts.size());
        Map<String, Object> first = (Map<String, Object>) contacts[0];
        Assert.isTrue(String.valueOf(first.get('phone')).startsWith('91'), 'Fonada phone format');
        Assert.areEqual(first.get('name'), first.get('BODY_1'));
        Assert.areEqual('DIWALI20', first.get('BODY_2'));
        Assert.areEqual('31 Oct', first.get('BODY_3'));

        Fonada_Campaign_Launch__c log = [SELECT Channel__c, Fonada_Agent__c, People_Queued__c FROM Fonada_Campaign_Launch__c];
        Assert.areEqual('WhatsApp', log.Channel__c);
        Assert.areEqual('WhatsApp template diwali_offer', log.Fonada_Agent__c);
        Assert.areEqual(2, log.People_Queued__c);
    }

    @IsTest
    static void whatsappDraftIsNotReportedAsSent() {
        FonadaServer s = new FonadaServer();
        s.toolText.put('whatsapp_send_campaign',
            '{"id":"wa-2","name":"Draft one","status":"DRAFT","launched":false,"launch_error":"template not approved"}');
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('WhatsApp', 'new_tpl');
        r.accountName = 'Msg Test Bank';
        r.whatsappAccountId = 'waba-9';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('false', res.success);
        Assert.isTrue(res.message.contains('as a draft') && res.message.contains('template not approved'), res.message);
        Assert.areEqual('waba-9', s.argsByTool.get('whatsapp_send_campaign').get('account_id'));
        Assert.areEqual(0, [SELECT COUNT() FROM Fonada_Campaign_Launch__c], 'a draft is not logged as a launch');
    }

    @IsTest
    static void rcsResolvesTemplateNameAndMapsVariables() {
        FonadaServer s = rcsServer();
        s.toolText.put('rcs_list_templates', '{"result":[{"id":"' + TPL_ID + '","template_name":"Diwali_Offer"}]}');
        Test.setMock(HttpCalloutMock.class, s);
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Two'];
        FonadaSendMessageCampaign.Request r = req('RCS', 'diwali_offer');
        r.recordId = c.Id;
        r.nameVariable = 'customer_name';
        r.rcsBotName = 'travel-helper';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();

        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('rcs-77', res.fonadaCampaignId);
        Assert.areEqual(new List<String>{ 'rcs_list_bots', 'rcs_list_templates', 'rcs_run_campaign' }, s.tools);
        Assert.areEqual('bot-1', s.argsByTool.get('rcs_list_templates').get('bot_id'), 'only the named bot is read');
        Map<String, Object> args = s.argsByTool.get('rcs_run_campaign');
        Assert.areEqual(TPL_ID, args.get('template_id'));
        Assert.areEqual('91', args.get('country_code'));
        Map<String, Object> mapping = (Map<String, Object>) args.get('parameter_mapping');
        Assert.areEqual('customer_name', mapping.get('customer_name'));
        Map<String, Object> row = (Map<String, Object>) ((List<Object>) args.get('contacts'))[0];
        Assert.areEqual('919300000002', row.get('phone'));
        Assert.areEqual('Ben Two', row.get('customer_name'));
        Assert.isTrue(res.message.contains('1 person from Contact Ben Two'), res.message);
    }

    @IsTest
    static void rcsUnknownTemplateListsTheAvailableOnes() {
        FonadaServer s = rcsServer();
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('rcs', 'nope');
        r.accountName = 'Msg Test Bank';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        FonadaSendMessageCampaign.Result noName = run(req('rcs', null));
        Test.stopTest();
        Assert.areEqual('false', res.success);
        Assert.isTrue(res.message.contains('No RCS template named "nope"'), res.message);
        Assert.isTrue(res.message.contains('diwali_offer [active] (bot Travel-helper)'), res.message);
        Assert.isTrue(noName.message.startsWith('Ask the user which RCS template'), noName.message);
        Assert.isFalse(s.tools.contains('rcs_run_campaign'), 'nothing may be sent');
    }

    @IsTest
    static void rcsSameTemplateOnTwoBotsAsksWhichBot() {
        FonadaServer s = rcsServer();
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('rcs', 'diwali_offer');
        r.accountName = 'Msg Test Bank';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();
        Assert.isTrue(res.message.contains('Several RCS bots'), res.message);
        Assert.isFalse(s.tools.contains('rcs_run_campaign'));
    }

    @IsTest
    static void rcsTemplateIdSkipsLookupAndDirectInternationalNumber() {
        FonadaServer s = rcsServer();
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('RCS', TPL_ID);
        r.phoneNumber = '+1 415 555 0100';
        r.personName = 'Walk-in';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual(new List<String>{ 'rcs_run_campaign' }, s.tools);
        Map<String, Object> row = (Map<String, Object>) ((List<Object>) s.argsByTool.get('rcs_run_campaign').get('contacts'))[0];
        Assert.areEqual('14155550100', row.get('phone'), 'no leading + for RCS');
    }

    @IsTest
    static void rcsBotProblems() {
        FonadaServer s = new FonadaServer();
        s.toolText.put('rcs_list_bots', '[]');
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('rcs', 'x');
        r.accountName = 'Msg Test Bank';
        Test.startTest();
        Assert.isTrue(run(r).message.contains('No RCS bot was found'));
        r.rcsBotName = 'Ghost';
        Assert.isTrue(run(r).message.contains('No RCS bot named "Ghost"'));
        s.toolError.put('rcs_list_bots', true);
        s.toolText.put('rcs_list_bots', 'RCS is not enabled');
        Assert.isTrue(run(r).message.contains('Could not list your RCS bots'));
        Test.stopTest();
    }

    @IsTest
    static void validationNeverSends() {
        FonadaServer s = new FonadaServer();
        Test.setMock(HttpCalloutMock.class, s);
        Assert.isTrue(run(req(null, 't')).message.contains('WhatsApp or RCS'));
        Assert.isTrue(run(req('email', 't')).message.contains('WhatsApp or RCS'));
        Assert.isTrue(run(req('whatsapp', null)).message.contains('whatsapp_list_templates'));
        FonadaSendMessageCampaign.Request bad = req('whatsapp', 't');
        bad.accountName = 'Msg Test Bank';
        bad.nameVariable = 'phone';
        Assert.isTrue(run(bad).message.contains('not a valid template variable'));
        bad.nameVariable = null;
        bad.extraVariables = 'NOEQUALS';
        Assert.isTrue(run(bad).message.contains('KEY=value'));
        bad.extraVariables = null;
        bad.accountName = 'Nope Inc';
        Assert.isTrue(run(bad).message.contains('No Salesforce Account'));
        insert new Account(Name = 'Empty Msg Co');
        bad.accountName = 'Empty Msg Co';
        Assert.isTrue(run(bad).message.contains('no message was sent'));
        bad.accountName = null;
        bad.phoneNumber = '12';
        Assert.isTrue(run(bad).message.contains('not a usable phone number'));
        Assert.isTrue(s.tools.isEmpty(), 'nothing may reach Fonada');
    }

    @IsTest
    static void doNotCallContactGetsNoMessage() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Two'];
        if (!FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'DoNotCall', AccessLevel.SYSTEM_MODE)) return;
        c.put('DoNotCall', true);
        update c;
        FonadaServer s = new FonadaServer();
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSettings.agentUserOverride = true;
        FonadaSendMessageCampaign.Request r = req('whatsapp', 't');
        r.recordId = c.Id;
        FonadaSendMessageCampaign.Result res = run(r);
        Assert.isTrue(res.message.contains('marked Do Not Call'), res.message);
        Assert.isTrue(s.tools.isEmpty());
    }

    @IsTest
    static void repeatSendIsGuardedPerTemplate() {
        FonadaServer s = new FonadaServer();
        s.toolText.put('whatsapp_send_campaign', '{"id":"wa-3","launched":true}');
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('whatsapp', 'diwali_offer');
        r.accountName = 'Msg Test Bank';
        Test.startTest();
        FonadaSendMessageCampaign.Result first = run(r);
        s.tools.clear();
        FonadaSendMessageCampaign.Result second = run(r);
        Test.stopTest();
        Assert.areEqual('true', first.success, first.message);
        Assert.areEqual('false', second.success);
        Assert.isTrue(second.message.contains('already started') && second.message.contains('send_message_campaign'),
            second.message);
        Assert.isTrue(s.tools.isEmpty(), 'a repeat must not reach Fonada');
    }

    @IsTest
    static void fonadaErrorIsShown() {
        FonadaServer s = new FonadaServer();
        s.toolError.put('whatsapp_send_campaign', true);
        s.toolText.put('whatsapp_send_campaign', 'Not found: No WhatsApp Business account is linked to this user.');
        Test.setMock(HttpCalloutMock.class, s);
        FonadaSendMessageCampaign.Request r = req('whatsapp', 'diwali_offer');
        r.accountName = 'Msg Test Bank';
        Test.startTest();
        FonadaSendMessageCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('false', res.success);
        Assert.isTrue(res.message.contains('No WhatsApp Business account is linked'), res.message);
    }

    @IsTest
    static void helpers() {
        Assert.areEqual('WhatsApp', FonadaSendMessageCampaign.normalizeChannel(' Whats App '));
        Assert.areEqual('WhatsApp', FonadaSendMessageCampaign.normalizeChannel('wa'));
        Assert.areEqual('RCS', FonadaSendMessageCampaign.normalizeChannel('rcs'));
        Assert.isNull(FonadaSendMessageCampaign.normalizeChannel('sms'));
        Map<String, String> extras = new Map<String, String>();
        Assert.isNull(FonadaSendMessageCampaign.parseExtras('A=1;;B=two {!x}', extras));
        Assert.areEqual('two { !x}', extras.get('B'));
        Assert.isNotNull(FonadaSendMessageCampaign.parseExtras('name=Bob', new Map<String, String>()));
        Assert.isNotNull(FonadaSendMessageCampaign.parseExtras('1bad=x', new Map<String, String>()));
    }
}
