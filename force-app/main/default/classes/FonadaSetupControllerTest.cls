@IsTest
private class FonadaSetupControllerTest {

    @IsTest
    static void renderFillsTheAgentUser() {
        String script = FonadaSetupController.render('agent@example.ext');
        Assert.isTrue(script.contains('default_agent_user: "agent@example.ext"'), 'username filled in');
        Assert.isFalse(script.contains(FonadaSetupController.PLACEHOLDER), 'placeholder replaced');
        Assert.isTrue(script.contains('mcpTool://FonadaAI__FonadaMCP/'), 'tool targets kept');
    }

    @IsTest
    static void modelOptions() {
        String claude = FonadaSetupController.render('a@x.ext', null);
        Assert.isTrue(claude.contains('model://sfdc_ai__DefaultBedrockAnthropicClaude45Sonnet'));
        String gpt = FonadaSetupController.render('a@x.ext', 'gpt-4-1');
        Assert.isTrue(gpt.contains('model://sfdc_ai__DefaultOpenAIGPT41'));
        Assert.isFalse(gpt.contains('Claude45Sonnet'));
        Assert.isTrue(FonadaSetupController.render('a@x.ext', 'gpt-4o-mini').contains('DefaultOpenAIGPT4OmniMini'));
        String orgDefault = FonadaSetupController.render('a@x.ext', 'default');
        Assert.isFalse(orgDefault.contains('Claude45Sonnet'), 'subagent model removed');
        Assert.isTrue(orgDefault.contains('DefaultEinsteinHyperClassifier'), 'router model kept');
        try {
            FonadaSetupController.render('a@x.ext', 'nope');
            Assert.fail('unknown model must be rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
        try {
            FonadaSetupController.buildScriptWithModel('', 'gpt-4-1');
            Assert.fail('blank user must be rejected');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }

    @IsTest
    static void templateHasThePlaceholder() {
        Assert.isTrue(FonadaSetupController.loadTemplate().contains(FonadaSetupController.PLACEHOLDER));
    }

    @IsTest
    static void namespacePrefixMatchesTheClass() {
        String ns = FonadaSetupController.namespacePrefix();
        String cls = FonadaSetupController.class.getName();
        Assert.areEqual(cls.contains('.') ? cls.substringBefore('.') : null, ns);
    }

    @IsTest
    static void buildScriptRejectsNonAgentUsers() {
        try {
            FonadaSetupController.buildScript(UserInfo.getUserName());
            Assert.fail('expected an exception for a non-agent user');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }

    @IsTest
    static void buildScriptRejectsBlank() {
        try {
            FonadaSetupController.buildScript('');
            Assert.fail('expected an exception for a blank username');
        } catch (AuraHandledException e) {
            Assert.isNotNull(e);
        }
    }

    @IsTest
    static void getAgentUsersReturnsOnlyAgentUsers() {
        List<FonadaSetupController.AgentUser> users = FonadaSetupController.getAgentUsers();
        Assert.isNotNull(users);
        for (FonadaSetupController.AgentUser u : users) {
            Assert.areNotEqual(UserInfo.getUserId(), u.userId, 'the admin is not an agent user');
            Assert.isFalse(u.username.startsWith('automatedclean'), 'system user excluded');
        }
    }

    @IsTest
    static void adminButtons() {
        Id psId = FonadaMCPPostInstall.resolvePermissionSetId();
        if (psId != null) {
            User u = new User(
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                Username = 'fonada.uninstall.' + System.currentTimeMillis() + '@example.com',
                Email = 'u@example.com', LastName = 'Uninstall', Alias = 'funin',
                TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
                EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
            insert u;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psId);
        }
        Test.startTest();
        Integer agents = FonadaSetupController.grantAgentAccess();
        Integer removed = FonadaSetupController.prepareUninstall();
        Test.stopTest();
        Assert.isTrue(agents >= 0);
        if (psId != null) {
            Assert.isTrue(removed >= 1, 'assignment removed');
            Assert.areEqual(0, [SELECT COUNT() FROM PermissionSetAssignment WHERE PermissionSetId = :psId]);
        }
    }

    @IsTest
    static void adminButtonsRejectNonAdmins() {
        User u = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            Username = 'fonada.nonadmin.' + System.currentTimeMillis() + '@example.com',
            Email = 'n@example.com', LastName = 'NonAdmin', Alias = 'fnadm',
            TimeZoneSidKey = 'Asia/Kolkata', LocaleSidKey = 'en_IN',
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US');
        insert u;
        System.runAs(u) {
            try {
                FonadaSetupController.prepareUninstall();
                Assert.fail('non-admin must be rejected');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
            try {
                FonadaSetupController.getAgentUsers();
                Assert.fail('non-admin must not list agent users');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
            try {
                FonadaSetupController.buildScriptWithModel('x@y.ext', null);
                Assert.fail('non-admin must not build scripts');
            } catch (AuraHandledException e) {
                Assert.isNotNull(e);
            }
        }
    }

    @IsTest
    static void buildScriptWorksForARealAgentUser() {
        List<FonadaSetupController.AgentUser> users = FonadaSetupController.getAgentUsers();
        if (users.isEmpty()) return;   // org without agent users: covered by renderFillsTheAgentUser
        String script = FonadaSetupController.buildScript(users[0].username);
        Assert.isTrue(script.contains(users[0].username));
    }

    @IsTest
    static void prepareUninstallRemovesTheCredentialReadPermSet() {
        Id credPs = FonadaMCPAgentAccess.ensureCredentialReadPermSet();
        insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = credPs);
        Test.startTest();
        Integer removed = FonadaSetupController.prepareUninstall();
        Test.stopTest();
        Assert.isTrue(removed >= 1, 'credential-read assignment removed');
        Assert.areEqual(0, [SELECT COUNT() FROM PermissionSet WHERE Id = :credPs], 'runtime permission set deleted');
    }
}
