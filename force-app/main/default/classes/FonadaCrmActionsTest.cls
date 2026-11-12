@IsTest
private class FonadaCrmActionsTest {

    @TestSetup
    static void data() {
        Account acc = new Account(Name = 'Fonada Test Bank');
        insert acc;
        insert new List<Contact>{
            new Contact(FirstName = 'Priyam', LastName = 'Paul', AccountId = acc.Id, Phone = '09310997248'),
            new Contact(FirstName = 'Mobile', LastName = 'Only', AccountId = acc.Id, MobilePhone = '+91 98765 43210'),
            new Contact(FirstName = 'No', LastName = 'Phone', AccountId = acc.Id),
            new Contact(FirstName = 'Dup', LastName = 'Number', AccountId = acc.Id, Phone = '9310997248')
        };
        insert new Lead(FirstName = 'Rahul', LastName = 'Lead', Company = 'Demo Co', Phone = '9123456789');
    }

    // ---- FonadaPhone

    @IsTest
    static void phoneNormalisation() {
        Assert.areEqual('919310997248', FonadaPhone.toDialNumber('09310997248'));
        Assert.areEqual('919310997248', FonadaPhone.toDialNumber('9310997248'));
        Assert.areEqual('919310997248', FonadaPhone.toDialNumber('+91 93109 97248'));
        Assert.areEqual('919310997248', FonadaPhone.toDialNumber('919310997248'));
        Assert.areEqual('919310997248', FonadaPhone.toDialNumber('0091 9310997248'));
        Assert.areEqual('+14155550100', FonadaPhone.toDialNumber('+1 (415) 555-0100'));
        Assert.areEqual('+14155550100', FonadaPhone.toDialNumber('0014155550100'));
        Assert.isNull(FonadaPhone.toDialNumber(''));
        Assert.isNull(FonadaPhone.toDialNumber('n/a'));
        Assert.isNull(FonadaPhone.toDialNumber('123'));
        Assert.areEqual('919310997248', FonadaPhone.firstDialNumber(new List<String>{ null, '9310997248' }));
        Assert.isNull(FonadaPhone.firstDialNumber(new List<String>{ null, '' }));
    }

    // ---- FonadaFindRecord

    private static FonadaFindRecord.Result find(String name, String type) {
        FonadaFindRecord.Request r = new FonadaFindRecord.Request();
        r.name = name;
        r.recordType = type;
        return FonadaFindRecord.find(new List<FonadaFindRecord.Request>{ r })[0];
    }

    @IsTest
    static void findsContactByExactName() {
        FonadaFindRecord.Result r = find('Priyam Paul', null);
        Assert.areEqual('true', r.found);
        Assert.areEqual('Contact', r.recordType);
        Assert.areEqual('Priyam Paul', r.fullName);
        Assert.areEqual('Fonada Test Bank', r.company);
        Assert.areEqual('09310997248', r.phone);
        Assert.areEqual('919310997248', r.dialNumber);
    }

    @IsTest
    static void findsLead() {
        FonadaFindRecord.Result r = find('Rahul', 'Lead');
        Assert.areEqual('true', r.found);
        Assert.areEqual('Lead', r.recordType);
        Assert.areEqual('Demo Co', r.company);
        Assert.areEqual('919123456789', r.dialNumber);
    }

    @IsTest
    static void contactWithoutPhone() {
        FonadaFindRecord.Result r = find('No Phone', 'Contact');
        Assert.areEqual('true', r.found);
        Assert.isNull(r.dialNumber);
        Assert.isTrue(r.message.contains('no usable phone'));
    }

    @IsTest
    static void partialNameListsOtherMatches() {
        FonadaFindRecord.Result r = find('o', 'Contact');   // matches several contacts
        Assert.areEqual('true', r.found);
        Assert.isTrue(String.isNotBlank(r.otherMatches));
    }

    @IsTest
    static void notFoundAndBlank() {
        Assert.areEqual('false', find('Nobody Here', null).found);
        FonadaFindRecord.Result blank = find('  ', null);
        Assert.areEqual('false', blank.found);
        Assert.isTrue(blank.message.contains('No name'));
    }

    // ---- FonadaGetCallList

    private static FonadaGetCallList.Result callList(String campaign, String account, String max) {
        FonadaGetCallList.Request r = new FonadaGetCallList.Request();
        r.campaignName = campaign;
        r.accountName = account;
        r.maxRecords = max;
        return FonadaGetCallList.build(new List<FonadaGetCallList.Request>{ r })[0];
    }

    @IsTest
    static void callListFromAccountDedupesAndSkips() {
        FonadaGetCallList.Result r = callList(null, 'Fonada Test', null);
        Assert.areEqual('Account Fonada Test Bank', r.source);
        Assert.areEqual('2', r.count, 'Priyam + Mobile Only; duplicate and no-phone skipped');
        Assert.areEqual('2', r.skipped);
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(r.leadsJson);
        Assert.areEqual(2, rows.size());
        Map<String, Object> first = (Map<String, Object>) rows[0];
        Assert.isTrue(first.containsKey('phone') && first.containsKey('name'));
        Map<String, Object> sched = (Map<String, Object>) JSON.deserializeUntyped(r.suggestedSchedule);
        Assert.isTrue(sched.containsKey('schedule_day'));
    }

    @IsTest
    static void callListRespectsMax() {
        FonadaGetCallList.Result r = callList(null, 'Fonada Test Bank', '1');
        Assert.areEqual('1', r.count);
    }

    @IsTest
    static void callListFromCampaign() {
        User marketer = new User(
            ProfileId = UserInfo.getProfileId(),
            Username = 'fonada.marketer.' + System.currentTimeMillis() + '@example.com',
            Email = 'marketer@example.com', LastName = 'Marketer', Alias = 'fmkt',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            UserPermissionsMarketingUser = true);
        insert marketer;
        System.runAs(marketer) {
            Campaign c = new Campaign(Name = 'Loan Due November', IsActive = true);
            insert c;
            Contact priyam = [SELECT Id FROM Contact WHERE LastName = 'Paul' LIMIT 1];
            Lead rahul = [SELECT Id FROM Lead LIMIT 1];
            insert new List<CampaignMember>{
                new CampaignMember(CampaignId = c.Id, ContactId = priyam.Id),
                new CampaignMember(CampaignId = c.Id, LeadId = rahul.Id)
            };
            FonadaGetCallList.Result r = callList('Loan Due', null, '50');
            Assert.areEqual('Campaign Loan Due November', r.source);
            Assert.areEqual('2', r.count);
            Assert.isTrue(r.leadsJson.contains('919310997248'));
            Assert.isTrue(r.leadsJson.contains('919123456789'));
        }
    }

    @IsTest
    static void callListErrors() {
        Assert.isTrue(callList(null, null, null).message.contains('Ask the user'));
        Assert.isTrue(callList('No Such Campaign', null, null).message.contains('No Salesforce Campaign'));
        Assert.isTrue(callList(null, 'No Such Account', null).message.contains('No Salesforce Account'));
    }

    @IsTest
    static void accountWithoutPhones() {
        insert new Account(Name = 'Empty Co');
        FonadaGetCallList.Result r = callList(null, 'Empty Co', null);
        Assert.areEqual('0', r.count);
        Assert.isTrue(r.message.contains('no people'));
    }

    @IsTest
    static void parseMaxAndSchedule() {
        Assert.areEqual(200, FonadaGetCallList.parseMax(null));
        Assert.areEqual(200, FonadaGetCallList.parseMax('abc'));
        Assert.areEqual(200, FonadaGetCallList.parseMax('0'));
        Assert.areEqual(1000, FonadaGetCallList.parseMax('5000'));
        // 22:30 IST -> window must stop at 23:59 the same day
        Datetime late = Datetime.newInstanceGmt(2026, 11, 10, 17, 0, 0);
        Map<String, Object> s = (Map<String, Object>) JSON.deserializeUntyped(FonadaGetCallList.suggestedSchedule(late));
        Assert.areEqual('2026-11-10', s.get('schedule_day'));
        Assert.areEqual('22:32', s.get('schedule_start_dtm'));
        Assert.areEqual('23:59', s.get('schedule_end_dtm'));
    }

    // ---- Security and settings (1.3.0)

    @IsTest
    static void doNotCallRecordsAreSkippedByDefault() {
        FonadaSettings.agentUserOverride = true;   // the Agentforce agent-user path (system mode)
        Account acc = [SELECT Id FROM Account WHERE Name = 'Fonada Test Bank'];
        insert new Contact(FirstName = 'Dnd', LastName = 'Person', AccountId = acc.Id,
            Phone = '9555555555', DoNotCall = true);
        FonadaGetCallList.Result r = callList(null, 'Fonada Test Bank', null);
        Assert.areEqual('2', r.count, 'Do Not Call contact must not be in the list');
        Assert.isFalse(r.leadsJson.contains('919555555555'));
        Assert.isTrue(r.message.contains('Do Not Call'), r.message);

        FonadaFindRecord.Result f = find('Dnd Person', 'Contact');
        Assert.areEqual('true', f.found);
        Assert.areEqual('true', f.doNotCall);
        Assert.isNull(f.dialNumber, 'Do Not Call record must get no dial number');
        Assert.isTrue(f.message.contains('Do Not Call'));

        FonadaSettings.testOverride = new Fonada_Settings__c(Include_Do_Not_Call__c = true);
        Assert.areEqual('3', callList(null, 'Fonada Test Bank', null).count, 'admin may allow Do Not Call');
        Assert.areEqual('919555555555', find('Dnd Person', 'Contact').dialNumber);
    }

    @IsTest
    static void crmActionsCanBeDisabled() {
        FonadaSettings.testOverride = new Fonada_Settings__c(Disable_CRM_Actions__c = true);
        Assert.isTrue(callList(null, 'Fonada Test Bank', null).message.contains('turned off'));
        FonadaFindRecord.Result f = find('Priyam Paul', null);
        Assert.areEqual('false', f.found);
        Assert.isTrue(f.message.contains('turned off'));
    }

    @IsTest
    static void wildcardsMatchLiterally() {
        Assert.areEqual('false', find('%', null).found, '% must not match every record');
        Assert.areEqual('false', find('_', null).found, '_ must not match every record');
        Assert.isTrue(callList('%', null, null).message.contains('No Salesforce Campaign'));
        Assert.areEqual('100\\%\\_x\\\\', FonadaSettings.escapeLike('100%_x\\'));
    }

    @IsTest
    static void ambiguousAccountIsNotPickedSilently() {
        insert new List<Account>{ new Account(Name = 'Twin Alpha Ltd'), new Account(Name = 'Twin Beta Ltd') };
        FonadaGetCallList.Result r = callList(null, 'Twin', null);
        Assert.areEqual('0', r.count);
        Assert.isTrue(r.message.contains('Several Salesforce Accounts match'), r.message);
        Assert.isTrue(r.message.contains('Twin Alpha Ltd') && r.message.contains('Twin Beta Ltd'));
        // an exact name wins over partial matches
        insert new Account(Name = 'Twin');
        Assert.areEqual('Account Twin', callList(null, 'Twin', null).source);
    }

    @IsTest
    static void recordIdTakesPriority() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Fonada Test Bank'];
        FonadaGetCallList.Request req = new FonadaGetCallList.Request();
        req.recordId = acc.Id;
        req.accountName = 'something else';
        FonadaGetCallList.Result r = FonadaGetCallList.build(new List<FonadaGetCallList.Request>{ req })[0];
        Assert.areEqual('Account Fonada Test Bank', r.source);
        Assert.areEqual(String.valueOf(acc.Id), r.sourceId);
        Assert.areEqual('2', r.count);

        req.recordId = 'not-an-id';
        Assert.isTrue(FonadaGetCallList.build(new List<FonadaGetCallList.Request>{ req })[0].message.contains('not a valid'));
        req.recordId = UserInfo.getUserId();
        Assert.isTrue(FonadaGetCallList.build(new List<FonadaGetCallList.Request>{ req })[0].message.contains('must belong'));
        Id deletedId = acc.Id;
        delete [SELECT Id FROM Contact WHERE AccountId = :deletedId];
        delete acc;
        req.recordId = deletedId;
        Assert.isTrue(FonadaGetCallList.build(new List<FonadaGetCallList.Request>{ req })[0].message.contains('No Salesforce Account with Id'));
    }

    @IsTest
    static void agentUsersReadInSystemModeOthersInUserMode() {
        FonadaSettings.agentUserOverride = true;
        Assert.areEqual(AccessLevel.SYSTEM_MODE, FonadaSettings.crmAccessLevel());
        Assert.areEqual('2', callList(null, 'Fonada Test Bank', null).count);
        FonadaSettings.agentUserOverride = false;
        Assert.areEqual(AccessLevel.USER_MODE, FonadaSettings.crmAccessLevel());
        FonadaSettings.agentUserOverride = null;
        Assert.areEqual(AccessLevel.USER_MODE, FonadaSettings.crmAccessLevel(), 'the test admin is not an agent user');
    }

    @IsTest
    static void userModeHidesRecordsThePersonCannotSee() {
        User reader = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            Username = 'fonada.reader.' + System.currentTimeMillis() + '@example.com',
            Email = 'reader@example.com', LastName = 'Reader', Alias = 'frdr',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert reader;
        System.runAs(reader) {
            // The reader may or may not see the records depending on the org-wide defaults; the
            // action must never fail and never return more than the reader can see.
            FonadaFindRecord.Result f = find('Priyam Paul', null);
            Integer visible = [SELECT COUNT() FROM Contact WHERE Name = 'Priyam Paul' WITH USER_MODE];
            if (visible == 0) Assert.areEqual('false', f.found, 'records the person cannot see must not be returned');
            Assert.isNotNull(f.message);
        }
    }

    @IsTest
    static void countryCodeAndTextCleaning() {
        Assert.areEqual('14155550100', FonadaPhone.toDialNumber('(415) 555-0100', '1'));
        Assert.areEqual('+919310997248', FonadaPhone.toDialNumber('+91 93109 97248', '1'));  // foreign + number kept international
        FonadaSettings.testOverride = new Fonada_Settings__c(Default_Country_Code__c = '+1');
        Assert.areEqual('1', FonadaSettings.countryCode());
        Assert.areEqual('14155550100', FonadaPhone.toDialNumber('4155550100'));
        FonadaSettings.testOverride = new Fonada_Settings__c();
        Assert.areEqual('91', FonadaSettings.countryCode());
        Assert.isTrue(FonadaSettings.crmActionsEnabled());
        Assert.isTrue(FonadaSettings.autoAccessEnabled());
        Assert.isFalse(FonadaSettings.includeDoNotCall());

        Assert.areEqual('a b { !$Credential.X}', FonadaSettings.cleanText('a\nb {!$Credential.X}', 80));
        Assert.areEqual('abc', FonadaSettings.cleanText('abcdef', 3));
        Assert.isNull(FonadaSettings.cleanText(null, 5));
    }

    @IsTest
    static void largeListsReportMembersNotIncluded() {
        Account big = new Account(Name = 'Big List Co');
        insert big;
        List<Contact> many = new List<Contact>();
        for (Integer i = 0; i < 5; i++) {
            many.add(new Contact(LastName = 'Big' + i, AccountId = big.Id, Phone = '93100000' + (10 + i)));
        }
        insert many;
        FonadaGetCallList.Result r = callList(null, 'Big List Co', '2');   // reads at most 4 of 5
        Assert.areEqual('2', r.count);
        Assert.isTrue(r.message.contains('1 more members were not included'), r.message);
    }

    @IsTest
    static void doNotCallCheckAdaptsToFieldAccess() {
        Assert.isTrue(FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'Phone', AccessLevel.SYSTEM_MODE));
        Assert.isFalse(FonadaSettings.fieldUsable(Schema.Contact.SObjectType, 'No_Such_Field__x', AccessLevel.SYSTEM_MODE));
        // In user mode the field is used only when the person can read it; the action never fails either way.
        FonadaSettings.agentUserOverride = false;
        Assert.areEqual('2', callList(null, 'Fonada Test Bank', null).count);
    }
}
