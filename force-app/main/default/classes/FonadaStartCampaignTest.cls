@IsTest
private class FonadaStartCampaignTest {

    private class FonadaMock implements HttpCalloutMock {
        Integer status;
        String body;
        String lastRequest;
        FonadaMock(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            lastRequest = req.getBody();
            HttpResponse res = new HttpResponse();
            res.setStatusCode(status);
            res.setBody(body);
            return res;
        }
    }

    private static String sse(String toolText, Boolean isError) {
        Map<String, Object> rpc = new Map<String, Object>{
            'jsonrpc' => '2.0', 'id' => 1,
            'result' => new Map<String, Object>{
                'content' => new List<Object>{ new Map<String, Object>{ 'type' => 'text', 'text' => toolText } },
                'isError' => isError
            }
        };
        return 'event: message\ndata: ' + JSON.serialize(rpc) + '\n\n';
    }

    @TestSetup
    static void data() {
        Account acc = new Account(Name = 'Start Test Bank');
        insert acc;
        insert new List<Contact>{
            new Contact(FirstName = 'Asha', LastName = 'One', AccountId = acc.Id, Phone = '9300000001'),
            new Contact(FirstName = 'Ben', LastName = 'Two', AccountId = acc.Id, Phone = '+91 93000 00002'),
            new Contact(FirstName = 'No', LastName = 'Number', AccountId = acc.Id)
        };
    }

    /** Fixed clock (10:00 IST on 2026-11-10) so schedule checks never depend on the real date. */
    private static final Datetime TEN_AM_IST = Datetime.newInstanceGmt(2026, 11, 10, 4, 30, 0);

    private static FonadaStartCampaign.Result run(FonadaStartCampaign.Request r) {
        if (FonadaGetCallList.nowOverride == null) FonadaGetCallList.nowOverride = TEN_AM_IST;
        return FonadaStartCampaign.start(new List<FonadaStartCampaign.Request>{ r })[0];
    }

    private static FonadaStartCampaign.Request req(String agent, String account) {
        FonadaStartCampaign.Request r = new FonadaStartCampaign.Request();
        r.fonadaAgent = agent;
        r.accountName = account;
        return r;
    }

    @IsTest
    static void startsCampaignWithExactPayload() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"abc-123","name":"Start Test Bank 2026-11-10 10:00","status":"active"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaGetCallList.nowOverride = Datetime.newInstanceGmt(2026, 11, 10, 4, 30, 0);   // 10:00 IST
        Test.startTest();
        FonadaStartCampaign.Result r = run(req('main_bot', 'Start Test'));
        Test.stopTest();

        Assert.areEqual('true', r.success, r.message);
        Assert.areEqual('abc-123', r.fonadaCampaignId);
        Assert.areEqual('2', r.peopleQueued);
        Assert.areEqual('1', r.skipped);
        Assert.areEqual('2026-11-10 10:02–13:00 IST', r.schedule);

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest);
        Assert.areEqual('tools/call', body.get('method'));
        Map<String, Object> params = (Map<String, Object>) body.get('params');
        Assert.areEqual('voice_campaigns_create_outbound', params.get('name'));
        Map<String, Object> args = (Map<String, Object>) params.get('arguments');
        Assert.areEqual('main_bot', args.get('agent'));
        Assert.isTrue(args.get('csv_rows') instanceof List<Object>, 'csv_rows must be a real list');
        Assert.isTrue(args.get('schedule') instanceof Map<String, Object>, 'schedule must be a real object');
        Assert.areEqual(2, ((List<Object>) args.get('csv_rows')).size());
        Assert.isTrue(mock.lastRequest.contains('919300000001'));
    }

    @IsTest
    static void customScheduleAndTitle() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"x1","name":"My Title"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', 'Start Test Bank');
        r.campaignTitle = 'My Title';
        r.scheduleDay = '2026-12-01';
        r.startTime = '9:30';
        r.maxRecords = '1';
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('My Title', res.fonadaCampaignName);
        Assert.areEqual('2026-12-01 09:30–23:59 IST', res.schedule);
        Assert.areEqual('1', res.peopleQueued);
    }

    @IsTest
    static void fonadaToolError() {
        Test.setMock(HttpCalloutMock.class, new FonadaMock(200, sse('TypeError: agent not found', true)));
        Test.startTest();
        FonadaStartCampaign.Result r = run(req('missing_bot', 'Start Test Bank'));
        Test.stopTest();
        Assert.areEqual('false', r.success);
        Assert.isTrue(r.message.contains('TypeError: agent not found'), r.message);
    }

    @IsTest
    static void httpErrors() {
        Test.setMock(HttpCalloutMock.class, new FonadaMock(401, '{"error":"missing_api_key"}'));
        Test.startTest();
        FonadaStartCampaign.Result r = run(req('main_bot', 'Start Test Bank'));
        Test.stopTest();
        Assert.areEqual('false', r.success);
        Assert.isTrue(r.message.contains('API key'), r.message);
    }

    @IsTest
    static void jsonRpcErrorAndServerError() {
        FonadaMcpClient.ToolResult a = FonadaMcpClient.parse(
            '{"jsonrpc":"2.0","id":1,"error":{"code":-32602,"message":"Unknown tool"}}', new FonadaMcpClient.ToolResult());
        Assert.isFalse(a.ok);
        Assert.areEqual('Unknown tool', a.error);
        FonadaMcpClient.ToolResult b = FonadaMcpClient.parse('not json', new FonadaMcpClient.ToolResult());
        Assert.isFalse(b.ok);
        FonadaMcpClient.ToolResult c = FonadaMcpClient.parse(sse('plain text result', false), new FonadaMcpClient.ToolResult());
        Assert.isTrue(c.ok);
        Assert.isNull(c.data);
        Assert.isTrue(FonadaMcpClient.endpoint().startsWith('callout:'));

        Test.setMock(HttpCalloutMock.class, new FonadaMock(500, 'boom'));
        Test.startTest();
        FonadaStartCampaign.Result r = run(req('main_bot', 'Start Test Bank'));
        Test.stopTest();
        Assert.isTrue(r.message.contains('HTTP 500'), r.message);
    }

    @IsTest
    static void validation() {
        Assert.isTrue(run(req(null, 'Start Test Bank')).message.contains('Fonada telephony agent'));
        Assert.isTrue(run(req('main_bot', null)).message.contains('Ask the user'));
        Assert.isTrue(run(req('main_bot', 'Nope Inc')).message.contains('No Salesforce Account'));
        insert new Account(Name = 'Empty Start Co');
        Assert.isTrue(run(req('main_bot', 'Empty Start Co')).message.contains('no people'));

        FonadaStartCampaign.Request bad = req('main_bot', 'Start Test Bank');
        bad.scheduleDay = 'tomorrow';
        Assert.isTrue(run(bad).message.contains('Schedule day'));
        bad.scheduleDay = null;
        bad.startTime = '10am';
        Assert.isTrue(run(bad).message.contains('Start time'));
        bad.startTime = null;
        bad.endTime = 'late';
        Assert.isTrue(run(bad).message.contains('End time'));
    }

    @IsTest
    static void scheduleChecks() {
        FonadaStartCampaign.Request r = req('main_bot', 'Start Test Bank');
        r.scheduleDay = '2026-11-09';                                     // yesterday
        Assert.isTrue(run(r).message.contains('in the past'));
        r.scheduleDay = '2026-02-30';                                     // not a real date
        Assert.isTrue(run(r).message.contains('real date'));
        r.scheduleDay = '2026-12-01';
        r.startTime = '25:00';                                            // impossible hour
        Assert.isTrue(run(r).message.contains('Start time'));
        r.startTime = '18:00';
        r.endTime = '17:00';                                              // ends before it starts
        Assert.isTrue(run(r).message.contains('must end after it starts'));
        Assert.isTrue(FonadaStartCampaign.isValidDay('2028-02-29'));
        Assert.isFalse(FonadaStartCampaign.isValidDay('2026-13-01'));
    }

    @IsTest
    static void pastStartTimeTodayStartsSoon() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"s1"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', 'Start Test Bank');
        r.startTime = '08:00';                                            // already past at 10:00 IST
        r.endTime = '12:00';
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('2026-11-10 10:02–12:00 IST', res.schedule);
    }

    @IsTest
    static void startsFromRecordIdAndNeutralisesMergeSyntax() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"r1","name":"x"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        Account acc = [SELECT Id FROM Account WHERE Name = 'Start Test Bank'];
        insert new Contact(FirstName = '{!$Credential.FonadaMCP.FonadaApiKey}', LastName = 'Evil',
            AccountId = acc.Id, Phone = '9300000009');
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.recordId = acc.Id;
        r.campaignTitle = 'Title {!$Credential.FonadaMCP.FonadaApiKey}';
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('3', res.peopleQueued);
        Assert.isFalse(mock.lastRequest.contains('{!'), 'no merge syntax may reach the callout body');
        Assert.isTrue(mock.lastRequest.contains('{ !$Credential'), 'text kept, merge syntax neutralised');
    }

    @IsTest
    static void parsesMultiFrameSse() {
        String progress = 'event: message\ndata: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progress":1}}\n\n';
        FonadaMcpClient.ToolResult tr = FonadaMcpClient.parse(
            progress + sse('{"id":"m1","name":"Multi"}', false), new FonadaMcpClient.ToolResult());
        Assert.isTrue(tr.ok, 'multi-frame response must parse: ' + tr.error);
        Assert.areEqual('m1', String.valueOf(tr.data.get('id')));
        FonadaMcpClient.ToolResult blank = FonadaMcpClient.parse('', new FonadaMcpClient.ToolResult());
        Assert.isFalse(blank.ok);
        Assert.areEqual('{"a":"{ !x}"}', FonadaMcpClient.safeBody(new Map<String, Object>{ 'a' => '{!x}' }));
    }

    @IsTest
    static void ambiguousSourceDoesNotLaunch() {
        insert new List<Account>{ new Account(Name = 'Dual One Pvt'), new Account(Name = 'Dual Two Pvt') };
        FonadaMock mock = new FonadaMock(200, sse('{"id":"never"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Result res = run(req('main_bot', 'Dual'));
        Assert.areEqual('false', res.success);
        Assert.isTrue(res.message.contains('Several Salesforce Accounts match'), res.message);
        Assert.isNull(mock.lastRequest, 'nothing may be sent to Fonada');
    }

    // ---- Repeat-launch guard -------------------------------------------------------------

    private static Fonada_Campaign_Launch__c priorLaunch(String agent) {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Start Test Bank'];
        return new Fonada_Campaign_Launch__c(Source_Id__c = acc.Id, Source_Name__c = 'Account Start Test Bank',
            Fonada_Agent__c = agent, Fonada_Campaign_Id__c = 'old-1');
    }

    @IsTest
    static void repeatLaunchIsRefusedAndLogged() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"g1","name":"Guarded"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        FonadaStartCampaign.Result first = run(req('main_bot', 'Start Test Bank'));
        mock.lastRequest = null;
        FonadaStartCampaign.Result second = run(req('MAIN_BOT', 'Start Test Bank'));
        Test.stopTest();
        Assert.areEqual('true', first.success, first.message);
        Fonada_Campaign_Launch__c log = [SELECT Source_Name__c, Fonada_Agent__c, Fonada_Campaign_Id__c,
            People_Queued__c, Schedule__c FROM Fonada_Campaign_Launch__c];
        Assert.areEqual('g1', log.Fonada_Campaign_Id__c);
        Assert.areEqual(2, log.People_Queued__c);
        Assert.areEqual('main_bot', log.Fonada_Agent__c);
        Assert.areEqual('false', second.success);
        Assert.isTrue(second.message.contains('already started'), second.message);
        Assert.isTrue(second.message.contains('g1'), second.message);
        Assert.isNull(mock.lastRequest, 'a repeat must not reach Fonada');
    }

    @IsTest
    static void allowRepeatStartsAgain() {
        insert priorLaunch('main_bot');
        FonadaMock mock = new FonadaMock(200, sse('{"id":"g2","name":"Again"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request blocked = req('main_bot', 'Start Test Bank');
        FonadaStartCampaign.Request again = req('main_bot', 'Start Test Bank');
        again.allowRepeat = 'TRUE';
        Test.startTest();
        FonadaStartCampaign.Result r1 = run(blocked);
        FonadaStartCampaign.Result r2 = run(again);
        Test.stopTest();
        Assert.areEqual('false', r1.success);
        Assert.isTrue(r1.message.contains('old-1'), r1.message);
        Assert.areEqual('true', r2.success, r2.message);
        Assert.areEqual(2, [SELECT COUNT() FROM Fonada_Campaign_Launch__c]);
    }

    @IsTest
    static void otherAgentStarts() {
        insert priorLaunch('main_bot');
        Test.setMock(HttpCalloutMock.class, new FonadaMock(200, sse('{"id":"g3"}', false)));
        Test.startTest();
        FonadaStartCampaign.Result otherAgent = run(req('payment_bot', 'Start Test Bank'));
        Test.stopTest();
        Assert.areEqual('true', otherAgent.success, otherAgent.message);
    }

    @IsTest
    static void guardOffStarts() {
        insert priorLaunch('main_bot');
        Test.setMock(HttpCalloutMock.class, new FonadaMock(200, sse('{"id":"g4"}', false)));
        FonadaSettings.testOverride = new Fonada_Settings__c(Repeat_Launch_Guard_Minutes__c = 0);
        Test.startTest();
        FonadaStartCampaign.Result guardOff = run(req('main_bot', 'Start Test Bank'));
        Test.stopTest();
        Assert.areEqual('true', guardOff.success, guardOff.message);
    }

    @IsTest
    static void bulkRequestsGuardEachOther() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"b1"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaGetCallList.nowOverride = TEN_AM_IST;
        Test.startTest();
        List<FonadaStartCampaign.Result> rs = FonadaStartCampaign.start(new List<FonadaStartCampaign.Request>{
            req('main_bot', 'Start Test Bank'), req('main_bot', 'Start Test Bank') });
        Test.stopTest();
        Assert.areEqual('true', rs[0].success, rs[0].message);
        Assert.areEqual('false', rs[1].success);
        Assert.isTrue(rs[1].message.contains('just now'), rs[1].message);
        Assert.areEqual(1, [SELECT COUNT() FROM Fonada_Campaign_Launch__c]);
    }

    @IsTest
    static void repeatGuardMinutesSetting() {
        FonadaSettings.testOverride = new Fonada_Settings__c();
        Assert.areEqual(10, FonadaSettings.repeatGuardMinutes());
        FonadaSettings.testOverride = new Fonada_Settings__c(Repeat_Launch_Guard_Minutes__c = -5);
        Assert.areEqual(0, FonadaSettings.repeatGuardMinutes());
        FonadaSettings.testOverride = new Fonada_Settings__c(Repeat_Launch_Guard_Minutes__c = 30);
        Assert.areEqual(30, FonadaSettings.repeatGuardMinutes());
    }

    // ---- MCP handshake -------------------------------------------------------------------

    /** Answers like an MCP server: initialize, notifications/initialized, tools/call. */
    private class HandshakeMock implements HttpCalloutMock {
        Integer initStatus;
        String initBody;
        List<String> methods = new List<String>();
        Map<String, String> toolHeaders = new Map<String, String>();
        HandshakeMock(Integer initStatus, String initBody) { this.initStatus = initStatus; this.initBody = initBody; }
        public HttpResponse respond(HttpRequest req) {
            String method = String.valueOf(((Map<String, Object>) JSON.deserializeUntyped(req.getBody())).get('method'));
            methods.add(method);
            HttpResponse res = new HttpResponse();
            if (method == 'initialize') {
                res.setStatusCode(initStatus);
                res.setBody(initBody);
                res.setHeader('Mcp-Session-Id', 'sess-1');
            } else if (method == 'notifications/initialized') {
                res.setStatusCode(202);
                res.setBody('');
            } else {
                toolHeaders.put('version', req.getHeader('MCP-Protocol-Version'));
                toolHeaders.put('session', req.getHeader('Mcp-Session-Id'));
                res.setStatusCode(200);
                res.setBody(sse('{"id":"h1"}', false));
            }
            return res;
        }
    }

    @IsTest
    static void handshakeSendsNegotiatedHeaders() {
        HandshakeMock mock = new HandshakeMock(200,
            'event: message\ndata: {"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2025-03-26","capabilities":{}}}\n\n');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        FonadaMcpClient.ToolResult tr = FonadaMcpClient.callTool('credits_get_balance', new Map<String, Object>());
        Test.stopTest();
        Assert.isTrue(tr.ok, 'tool call should succeed: ' + tr.error);
        Assert.areEqual(new List<String>{ 'initialize', 'notifications/initialized', 'tools/call' }, mock.methods);
        Assert.areEqual('2025-03-26', mock.toolHeaders.get('version'));
        Assert.areEqual('sess-1', mock.toolHeaders.get('session'));
    }

    @IsTest
    static void failedHandshakeFallsBackToPlainCall() {
        HandshakeMock mock = new HandshakeMock(500, 'oops');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        FonadaMcpClient.ToolResult tr = FonadaMcpClient.callTool('credits_get_balance', new Map<String, Object>());
        Test.stopTest();
        Assert.isTrue(tr.ok, 'tool call should succeed: ' + tr.error);
        Assert.areEqual(new List<String>{ 'initialize', 'tools/call' }, mock.methods);
        Assert.isNull(mock.toolHeaders.get('version'), 'no version header without a handshake');
        Assert.isNull(mock.toolHeaders.get('session'));
    }

    @IsTest
    static void handshakeKeyErrorStopsEarly() {
        HandshakeMock mock = new HandshakeMock(401, '{"error":"missing_api_key"}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        FonadaMcpClient.ToolResult tr = FonadaMcpClient.callTool('credits_get_balance', new Map<String, Object>());
        Test.stopTest();
        Assert.isFalse(tr.ok);
        Assert.isTrue(tr.error.contains('rejected the API key (HTTP 401)'), tr.error);
        Assert.areEqual(new List<String>{ 'initialize' }, mock.methods);
    }

    // ---- Single calls (one Contact, Lead or phone number via voice_campaigns_create_outbound) ----

    private static List<Object> sentRows(FonadaMock mock) {
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.lastRequest);
        Map<String, Object> params = (Map<String, Object>) body.get('params');
        Assert.areEqual('voice_campaigns_create_outbound', params.get('name'));
        return (List<Object>) ((Map<String, Object>) params.get('arguments')).get('csv_rows');
    }

    @IsTest
    static void singleContactCall() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'One'];
        FonadaMock mock = new FonadaMock(200, sse('{"id":"s1","name":"Asha One"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.recordId = c.Id;
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('1', res.peopleQueued);
        Assert.isTrue(res.message.contains('1 person from Contact Asha One'), res.message);
        List<Object> rows = sentRows(mock);
        Assert.areEqual(1, rows.size());
        Assert.areEqual('919300000001', ((Map<String, Object>) rows[0]).get('phone'));
        Assert.areEqual(String.valueOf(c.Id), [SELECT Source_Id__c FROM Fonada_Campaign_Launch__c].Source_Id__c);
    }

    @IsTest
    static void singleLeadCall() {
        Lead l = new Lead(FirstName = 'Lia', LastName = 'Lead', Company = 'Lead Co', MobilePhone = '09300000077');
        insert l;
        FonadaMock mock = new FonadaMock(200, sse('{"id":"s2"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.recordId = l.Id;
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Assert.areEqual('919300000077', ((Map<String, Object>) sentRows(mock)[0]).get('phone'));
    }

    @IsTest
    static void singleCallRespectsDoNotCallAndMissingPhone() {
        Contact c = [SELECT Id FROM Contact WHERE LastName = 'Two'];
        Boolean dncAvailable = FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'DoNotCall', AccessLevel.SYSTEM_MODE);
        if (dncAvailable) {
            c.put('DoNotCall', true);
            update c;
        }
        FonadaMock mock = new FonadaMock(200, sse('{"id":"never"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaSettings.agentUserOverride = true;
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.recordId = c.Id;
        FonadaStartCampaign.Result res = run(r);
        if (dncAvailable) {
            Assert.areEqual('false', res.success);
            Assert.isTrue(res.message.contains('marked Do Not Call'), res.message);
        }
        FonadaStartCampaign.Request noPhone = req('main_bot', null);
        noPhone.recordId = [SELECT Id FROM Contact WHERE LastName = 'Number'].Id;
        FonadaStartCampaign.Result res2 = run(noPhone);
        Assert.areEqual('false', res2.success);
        Assert.isTrue(res2.message.contains('no people with a usable phone'), res2.message);
        Assert.isNull(mock.lastRequest, 'nothing may be sent to Fonada');
    }

    @IsTest
    static void directPhoneCall() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"d1"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.phoneNumber = '+91 93109 97248';
        r.personName = 'Walk-in {!x}';
        Test.startTest();
        FonadaStartCampaign.Result res = run(r);
        FonadaStartCampaign.Result again = run(r);
        Test.stopTest();
        Assert.areEqual('true', res.success, res.message);
        Map<String, Object> row = (Map<String, Object>) sentRows(mock)[0];
        Assert.areEqual('919310997248', row.get('phone'));
        Assert.areEqual('Walk-in { !x}', row.get('name'));
        Assert.areEqual('false', again.success, 'same number twice within the guard window is refused');
        Assert.isTrue(again.message.contains('already started'), again.message);
    }

    @IsTest
    static void directPhoneValidation() {
        FonadaMock mock = new FonadaMock(200, sse('{"id":"never"}', false));
        Test.setMock(HttpCalloutMock.class, mock);
        FonadaStartCampaign.Request r = req('main_bot', null);
        r.phoneNumber = 'abc';
        Assert.isTrue(run(r).message.contains('not a usable phone number'));
        r.phoneNumber = '123';
        Assert.isTrue(run(r).message.contains('not a usable phone number'));
        FonadaSettings.testOverride = new Fonada_Settings__c(Disable_CRM_Actions__c = true);
        FonadaStartCampaign.Request withSource = req('main_bot', 'Start Test Bank');
        withSource.phoneNumber = '9310997248';
        Assert.isTrue(run(withSource).message.contains('turned off'), 'a CRM source is never replaced by the phone number');
        Assert.isNull(mock.lastRequest);
    }
}
