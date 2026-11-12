# Fonada MCP Agent: ready-made Agent Script

`main/default/aiAuthoringBundles/Fonada_MCP_Agent/Fonada_MCP_Agent.agent` is a complete Agentforce
agent. It contains:

- a **Fonada** subagent, with the routing Description and step-by-step Reasoning Instructions for
  "call contact X", "start a campaign for Salesforce Campaign/Account Y", pause/resume/stop and reports
- 19 Fonada MCP tools wired in as actions (`mcpTool://FonadaAI__FonadaMCP/<tool>`)
- 2 packaged Salesforce CRM actions (`apex://FonadaAI__FonadaFindRecord`,
  `apex://FonadaAI__FonadaGetCallList`): find a contact/lead, and build a call list from a
  Salesforce Campaign or Account, with phones already in Fonada dial format

No Messaging-channel variables: the script saves in orgs without Messaging set up.

**Keep in sync:** the package serves this file from
`force-app/main/default/staticresources/FonadaAgentTemplate.resource` (the Fonada Setup tab). Copy
this file there after every change.

It is **not** part of the managed package. Salesforce can't package Agent Script agents yet, so it
ships as a file that the customer publishes once. This directory is listed in `sfdx-project.json`
as an *unpackaged* directory.

## Use it (customer)

1. Install the **Fonada MCP** package and paste your `fsk_…` key. See the install guide.
2. Create an agent user. The package automatically gives it Fonada access:
   ```bash
   sf org create agent-user -o <org> --base-username fonada-agent@<your-domain>
   ```
3. Open the **Fonada Setup** tab (App Launcher), pick the agent user and click **Copy script**. Or
   replace `UPDATE_WITH_YOUR_DEFAULT_AGENT_USER` in the `.agent` file with that username yourself.
4. Publish and activate:
   ```bash
   # the bundle must sit in the default package directory to publish
   mkdir -p force-app/main/default/aiAuthoringBundles
   cp -r agent-script/main/default/aiAuthoringBundles/Fonada_MCP_Agent force-app/main/default/aiAuthoringBundles/
   sf agent publish authoring-bundle -o <org> -n Fonada_MCP_Agent
   sf agent activate -o <org> -n Fonada_MCP_Agent
   ```
   GUI alternative: Agentforce Builder → New Agent → open the **Script** view → paste the file → Save →
   pick the agent user → Activate.
5. Test it in Preview with "list my telephony agents".

## Rules learned while building it

- Keep each action to just `target:`. Drop `source:`, because that hash only exists in the org it
  was retrieved from.
- **Service agents** need `default_agent_user`. Without it, publish fails with *"Default agent user
  is required for the agent type EinsteinServiceAgent"*.
- **When the Fonada server changes a tool's description**, Salesforce blocks the call with
  `tool_definition_validation_failed`. To fix it:
  1. Regenerate the package ESR schema from the live server.
  2. Ship a new package version.
  3. Have customers **republish the agent**, because the agent stores tool definitions at publish
     time.

  Only change tool descriptions on the server when you release a new package version.
