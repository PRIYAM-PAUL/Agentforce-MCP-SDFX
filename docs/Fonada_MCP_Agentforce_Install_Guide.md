# Fonada MCP for Agentforce — Install & Usage Guide

Connect **Agentforce** to the **Fonada AI platform**. After installing, your agent can find Salesforce
contacts and leads and call them through Fonada. It can run outbound voice campaigns from a Salesforce
Campaign or Account, and send WhatsApp or RCS templates to the same people. It can also search your Fonada
knowledge base and check credits. You don't need a CSV: the call and message lists are built from your
Salesforce data.

> **Publisher:** Fonada · **Support:** support@fonada.ai · https://fonada.ai
> **In-app guide:** after installing, open the **App Launcher** and search for **Fonada Setup**.

---

## 1. What the package installs (automatically)

| Component | Purpose |
|---|---|
| MCP server **FonadaMCP** (Agentforce Registry) | The Fonada MCP server `https://mcp.fonada.ai/mcp`, with a curated set of Fonada tools |
| External Credential **FonadaMCP** | Stores your Fonada API key (`fsk_…`) securely |
| Named Credential **FonadaMCP** | The endpoint and the authentication header |
| Permission Set **Fonada MCP - Permission Set** | Access to the credential, the Fonada actions and the Fonada Setup tab |
| Actions **Fonada: Find Contact or Lead** and **Fonada: Get Call List** | Read names and phone numbers from Salesforce, so you can preview who will be contacted |
| Action **Fonada: Start Campaign** | Calls one Contact or Lead, a typed phone number, or everyone in a Salesforce Campaign or Account, in one step |
| Action **Fonada: Send Message Campaign** | Sends an approved WhatsApp or RCS template to the same kinds of recipients |
| Tab **Fonada Setup** | Builds the ready-to-paste agent, shows access status, and holds the usage guide, troubleshooting and uninstall help |
| Custom Setting **Fonada Settings** | Optional switches for admins (section 8). With no record, safe defaults apply. |
| Object **Fonada Campaign Launch** | Audit log of every campaign started from Salesforce. It also blocks accidental double launches. |
| Automation | Every Agentforce agent user gets Fonada access automatically, both on install and whenever a new agent user is created |

You don't create credentials, permission sets, flows or actions by hand.

## 2. Requirements

- A Salesforce org with **Einstein** and **Agentforce** (Enterprise, Unlimited, Developer or Agentforce editions).
- A **Fonada API key** (`fsk_…`) from your Fonada account.
- At least one **outbound telephony agent** in Fonada for calls. For messaging, you also need an approved
  **WhatsApp Business account / templates** or an approved **RCS bot / templates** in Fonada.
- A System Administrator to do the install.

## 3. Install

1. Click **Get It Now** on the listing (or open the install link) and log in to your org.
2. Choose **Install for All Users**, then click **Install**. Wait for the confirmation email.
3. To check: Setup → **Installed Packages** should show **Fonada MCP**.

## 4. Turn on Agentforce (if it's not already on)

- Setup → **Einstein Setup** → turn on Einstein.
- Setup → **Agentforce Agents** → On.

## 5. Paste your Fonada key

1. Setup → **Named Credentials** → **External Credentials** tab → **FonadaMCP**.
2. **Principals** → `MCPAuthentication` → ▾ **Edit** → **Authentication Parameters** → **Add**.
3. Name: `FonadaApiKey`. Value: your `fsk_…` key. Click **Save**.
4. To check: Setup → **Agentforce Registry** → MCP Servers → **FonadaMCP** → **Refresh**. The tools should be listed.

## 6. Create the agent (about 3 minutes)

1. App Launcher → **Agentforce Studio** → **Agentforce Builder** → **New Agent** → **Service agent** →
   **Create new user**. Give it a name (e.g. *Fonada Agent*), then click **Create**.
2. App Launcher → search **Fonada Setup** → **Refresh**.
   - Select the new agent user. Both access badges should be green.
   - Pick the AI model. **Claude Sonnet 4.5** is recommended; GPT-4.1, GPT-4o mini or your org's default
     are also available.
   - Click **Copy script**.
3. In the Builder, open your agent → **Script** view (`</>`).
   - Select all, paste, and click **Save**.
   - Click **Commit**, then **Activate**.
   - If you only Save without Commit, the Fonada tools aren't connected, and the agent will say it has no tool.
4. Open **Preview**, click **New conversation**, and try `list my telephony agents`.

## 7. Use it

| Type in the agent | What happens |
|---|---|
| `list my telephony agents` | Lists your Fonada voice agents |
| `find contact <name>` / `find lead <name>` | Finds the Salesforce record, with company and phone |
| `call contact <name> using <Fonada agent>` | Confirms the person, number and agent, then calls that one person (a 1-person Fonada campaign) |
| `call 93XXXXXXXX (name <name>) using <Fonada agent>` | Calls a number that isn't in Salesforce |
| `start a campaign for <Salesforce campaign> with <Fonada agent>` | Builds the list from the Campaign's contacts and leads, shows count and preview, asks you to confirm, then launches a Fonada outbound campaign (starting now, IST, unless you give a day or time window) |
| `call all contacts of account <account> with <Fonada agent>` | The same, using an Account's contacts |
| `send WhatsApp template <template> to campaign <campaign>` | Shows the recipients and the template, asks you to confirm, then sends a WhatsApp campaign |
| `send RCS template <template> to lead <name>` | The same over RCS (for one person, a Campaign or an Account) |
| `pause` / `resume` / `stop campaign X` | Manages the Fonada campaign (stopping is final, so it asks first) |
| `how did campaign X go` / `show the CDR for campaign X` | Shows dispositions, summary, KPIs and call records |
| `search the knowledge base of <agent> for <question>` | Searches the knowledge base of a Fonada agent |
| `what is my credit balance` | Shows your Fonada credit balance |

Calls, messages and campaigns spend Fonada credits. The agent always shows who will be contacted and asks you
to confirm first.

### Campaigns from Salesforce data

1. **Campaigns** tab → **New** → give it a name → **Save**. Creating Campaigns needs the **Marketing User**
   checkbox on your user.
2. From a Contacts or Leads list view or report, select people → **Add to Campaign**. Use report filters to
   choose exactly who is contacted.
3. In the agent: `start a campaign for <campaign name> with <Fonada agent>`, or
   `send WhatsApp template <template> to campaign <campaign name>`.

How the list is built:
- **Phone numbers** are converted to Fonada's format automatically (`093XXXXXXXX` → `9193XXXXXXXX`). National
  numbers get the default country code: 91 unless you change it in section 8.
- **Skipped people:** anyone without a phone number, duplicate numbers, and anyone marked **Do Not Call**. The
  agent tells you how many were skipped.
- **Size:** up to 200 people by default and 1,000 at most per launch. If there are more, the agent tells you how
  many were left out.
- **Matching names:** if a name matches several Campaigns, Accounts, Contacts or Leads, the agent lists them and
  asks which one you mean. It never picks one silently.
- **Double launches:** starting the same Campaign or Account again with the same Fonada agent (or template)
  within 10 minutes is refused unless you confirm you really want a second launch.

### WhatsApp and RCS templates with variables

If the template has a variable for the person's name, tell the agent its name, for example: `use BODY_1 for the
name`. For values that are the same for everyone, say for example `with offer=DIWALI20`. For RCS, if the
template name is wrong or missing, the agent shows the list of your RCS templates.

## 8. Fonada Settings (optional, admins)

Setup → **Custom Settings** → **Fonada Settings** → **Manage**. Org-level values apply to everyone, and profile
or user values override them. If no record exists, the defaults below apply.

| Setting | Default | Effect |
|---|---|---|
| Disable CRM actions | off | Stops the Fonada actions from reading Salesforce data (e.g. if the agent is ever placed on a public channel) |
| Include Do Not Call records | off | Not recommended: also contacts people marked Do Not Call |
| Disable automatic agent access | off | Stops new agent users from getting Fonada access automatically. Use **Fix agent access** in the Fonada Setup tab instead. |
| Default country code | 91 | Country code added to national numbers (digits only, e.g. `1` for the US) |
| Repeat launch guard (minutes) | 10 | Time window in which the same campaign can't be started twice. `0` turns the guard off. |

## 9. Extend it

- Add your own Flow or Apex actions to the **Fonada** subagent in Agentforce Builder.
- Edit the subagent's Description or Instructions to match your process.
- The agent is meant for **internal users**; don't deploy it on public or customer-facing channels.
- Employee (internal) agents run as the chatting user. Assign **Fonada MCP - Permission Set** and
  **Fonada MCP - Agent Credential Read** to those users. Their own Salesforce sharing and field access apply
  to the CRM actions.

## 10. Troubleshooting

| You see | Fix |
|---|---|
| `INVALID_API_INPUT` / named credential refresh failed | The key is missing or wrong. See section 5. |
| `credential_access_denied` | Fonada Setup → Troubleshooting → **Fix agent access** (or assign both Fonada permission sets to the agent user) |
| The agent says it has no tool for credits, agents, etc. | The script was saved but not committed. **Save → Commit → Activate → New conversation**. |
| "This campaign was already started a few minutes ago" | The double-launch guard. Say you want to start it again, or wait (section 8). |
| "Several records match" | Reply with the exact name, or pick one from the list the agent shows |
| "No WhatsApp Business account is linked" | Connect a WhatsApp Business account in Fonada first |
| RCS fails or a template isn't found | Your RCS bot must be approved in Fonada. Use one of the template names the agent lists. |
| WhatsApp campaign "saved as a draft but not sent" | Fix the problem it names in Fonada, then launch the draft from the Fonada dashboard |
| Off-topic reply | Mention Fonada, a contact, a campaign or a call, or re-paste the script |
| `tool_definition_validation_failed` | Install the latest Fonada MCP version and re-paste the script |
| The Script view won't save | Copy the script again from Fonada Setup without editing the `target` lines |
| "Sorry, it looks like something has gone wrong" on every message | Your org may not offer the selected AI model. In Fonada Setup, pick another model (GPT-4.1 or org default), then copy and paste the script again. |
| "Your session has ended" in Preview | Click **New conversation** after every Save or Commit |

## 11. Uninstall

1. In the Builder, deactivate and delete the Fonada agent.
2. App Launcher → **Fonada Setup** → tab **5. Uninstall** → **Prepare for uninstall**.
   - This removes every assignment of the Fonada permission sets, which would otherwise block the uninstall.
   - It also deletes the *Fonada MCP - Agent Credential Read* permission set that the package created.
   - Manual alternative: Setup → Permission Sets → **Fonada MCP - Permission Set** → Manage Assignments →
     remove all.
3. Setup → Installed Packages → Fonada MCP → **Uninstall**. Fonada Settings and the Fonada Campaign Launch log are
   removed with the package.

## 12. Security & data

- Your Fonada key is stored encrypted in the External Credential. It is never visible to users or to the
  package's code.
- The CRM actions only **read** Salesforce data: name, company, phone, email and the Do Not Call flag of the
  records the agent asks for. They never change your records.
  - For agent users, the actions read just these fields.
  - For employees, Salesforce sharing and field access apply.
- The only data the package writes is its own launch log. That log holds no contact data: only the source,
  the Fonada agent or template, the Fonada campaign id and name, the schedule and the count.
- Data sent to Fonada is limited to what a call, message or campaign needs: name and phone number, plus any
  template values you give.
- Support: support@fonada.ai
