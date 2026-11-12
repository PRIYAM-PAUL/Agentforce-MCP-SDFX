# Fonada MCP for Agentforce

A managed Salesforce package (2GP) that connects **Agentforce** to the **Fonada AI platform** over the Model
Context Protocol (MCP). Customers install the package, paste one Fonada API key, and paste a ready-made agent
script from the **Fonada Setup** tab. The agent can then:
- call Salesforce contacts and leads
- run voice campaigns from Salesforce Campaigns or Accounts
- send WhatsApp or RCS templates to the same people
- query the knowledge base and check credits

- **Endpoint:** `https://mcp.fonada.ai/mcp`
- **Namespace:** `FonadaAI` · **Package:** `Fonada MCP` (`0HodN0000000bcHSAQ`) · **Dev Hub:** `agentforce-org`
- **Released:** **Fonada MCP 1.0** = build **1.2.0.13** (`04tdN000000TfMLQA0`, coverage 94 %, promoted 2026-11-12)
- **Install URL:** https://login.salesforce.com/packaging/installPackage.apexp?p0=04tdN000000TfMLQA0
- **Publisher:** Fonada · **Support:** support@fonada.ai

---

## What the package installs

| Component | Purpose |
|---|---|
| `ExternalCredential` `FonadaMCP` | Holds the customer's `fsk_…` key (Custom protocol, principal `MCPAuthentication`, parameter `FonadaApiKey`) |
| `NamedCredential` `FonadaMCP` | Endpoint `https://mcp.fonada.ai/mcp`. `allowMergeFieldsInHeader` **must stay true** (the auth header uses it). |
| `ExternalServiceRegistration` `FonadaMCP` | MCP server in the Agentforce Registry with the baked tool schema (19 tools) |
| `PermissionSet` `FonadaMCP_Perm_Set` | Credential principal, the Apex actions and the Fonada Setup tab |
| Apex actions | `FonadaFindRecord`, `FonadaGetCallList`, `FonadaStartCampaign`, `FonadaSendMessageCampaign` |
| Apex support | `FonadaMcpClient` (JSON-RPC `tools/call` with the MCP handshake), `FonadaPhone`, `FonadaSettings`, `FonadaLaunchGuard` |
| Access automation | `FonadaMCPPostInstall`, `FonadaMCPAgentAccess`, `FonadaMCPAgentUserTrigger` (agent users get access automatically; creates the runtime perm set `Fonada_MCP_Agent_Credential_Read`) |
| Setup tab | `lwc/fonadaSetup` + `FonadaSetupController` + tab `Fonada_Setup` (5 tabs: setup, examples, campaigns, troubleshooting, uninstall) |
| Agent template | `staticresources/FonadaAgentTemplate` |
| Custom Setting | `Fonada_Settings__c` (hierarchy; empty = defaults) |
| Object | `Fonada_Campaign_Launch__c`: launch audit log + repeat-launch guard |

The agent template has 21 actions: 17 `mcpTool://FonadaAI__FonadaMCP/…` targets and 4 `apex://FonadaAI__…`
targets. Voice campaigns are started by Apex (`voice_campaigns_create_outbound`), and WhatsApp and RCS campaigns
also go through Apex (`whatsapp_send_campaign` / `rcs_run_campaign`). These tools aren't direct agent actions.
`voice_campaigns_test_single_call` is still in the registration but isn't used; a single call is a 1-person
campaign.

## Repository layout

```
force-app/main/default/
├── classes/                 # Apex actions, MCP client, access automation, tests
├── externalCredentials/  namedCredentials/  externalServiceRegistrations/
├── lwc/fonadaSetup/         # Fonada Setup tab (don't let Prettier reformat the HTML: LWC1043)
├── objects/                 # Fonada_Settings__c, Fonada_Campaign_Launch__c
├── permissionsets/  tabs/  triggers/
└── staticresources/FonadaAgentTemplate.resource   # must stay identical to the .agent below
agent-script/main/default/aiAuthoringBundles/Fonada_MCP_Agent/Fonada_MCP_Agent.agent   # not packaged
config/project-scratch-def.json
docs/
├── Fonada_MCP_Agentforce_Install_Guide.md   # customer-facing install & usage guide
├── AgentExchange_Listing_Content.md         # marketplace listing copy
├── Security_Review_Notes.md                 # internal notes for the security review
├── security-review/                         # Code Analyzer report (html/csv)
├── Salesforce_Implementation_README.md     # history up to 2026-11-02 (superseded)
└── source/                                  # day 1–2 history
```

## Build & release

```bash
# Before a build: no `sf agent publish` leftovers in force-app (aiAgents/, aiAgentDefinitionVersions/,
# FonadaAI__*.cls stubs), and the .agent file and the static resource must be identical.
sf package version create --package "Fonada MCP" --installation-key-bypass --code-coverage \
  --wait 60 --target-dev-hub agentforce-org

# Test install (package installs use --no-namespace scratch orgs)
sf org create scratch --definition-file config/project-scratch-def.json --alias <alias> \
  --duration-days 7 --no-namespace --target-dev-hub agentforce-org --wait 10
sf package install --package "Fonada MCP@<x.y.z-n>" --target-org <alias> --wait 20 --publish-wait 10 --no-prompt

# Release (cannot be undone; only one build per x.y.z can be released)
sf package version promote --package "Fonada MCP@<x.y.z-n>" --target-dev-hub agentforce-org --no-prompt
```

**Next version line:** in `sfdx-project.json`, set `versionNumber` to `1.3.0.NEXT` and `ancestorVersion` to
`1.2.0` before the next build. `versionName` stays `"Fonada MCP 1.0"` (that's the customer-facing name).
