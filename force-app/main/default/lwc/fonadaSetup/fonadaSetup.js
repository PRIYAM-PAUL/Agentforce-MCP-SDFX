import { LightningElement } from 'lwc';
import getAgentUsers from '@salesforce/apex/FonadaSetupController.getAgentUsers';
import buildScriptWithModel from '@salesforce/apex/FonadaSetupController.buildScriptWithModel';
import grantAgentAccess from '@salesforce/apex/FonadaSetupController.grantAgentAccess';
import prepareUninstall from '@salesforce/apex/FonadaSetupController.prepareUninstall';
import LightningConfirm from 'lightning/confirm';

export default class FonadaSetup extends LightningElement {
    users = [];
    selected;
    script = '';
    error;
    loading = false;
    copied = false;
    adminMessage;
    model = 'claude-sonnet-4-5';

    connectedCallback() {
        this.load();
    }

    async load() {
        this.loading = true;
        this.error = undefined;
        try {
            this.users = await getAgentUsers();
            const stillThere = this.users.some((u) => u.username === this.selected);
            if (!stillThere) this.selected = this.users.length ? this.users[0].username : undefined;
            await this.refreshScript();
        } catch (e) {
            this.error = this.message(e);
        } finally {
            this.loading = false;
        }
    }

    async refreshScript() {
        this.copied = false;
        this.script = this.selected ? await buildScriptWithModel({ username: this.selected, modelKey: this.model }) : '';
    }

    get options() {
        return this.users.map((u) => ({ label: `${u.name} — ${u.username}`, value: u.username }));
    }
    get modelOptions() {
        return [
            { label: 'Claude Sonnet 4.5 (recommended)', value: 'claude-sonnet-4-5' },
            { label: 'GPT-4.1', value: 'gpt-4-1' },
            { label: 'GPT-4o mini (faster, lower cost)', value: 'gpt-4o-mini' },
            { label: "Your org's default Agentforce model", value: 'default' }
        ];
    }

    async handleModel(event) {
        this.model = event.detail.value;
        try {
            await this.refreshScript();
        } catch (e) {
            this.error = this.message(e);
        }
    }

    get hasAgentUsers() { return !this.loading && this.users.length > 0; }
    get noAgentUsers() { return !this.loading && !this.error && this.users.length === 0; }
    get noScript() { return !this.script; }
    get selectedUser() { return this.users.find((u) => u.username === this.selected); }

    get accessLabel() { return this.selectedUser?.hasFonadaAccess ? 'Fonada access: yes' : 'Fonada access: missing'; }
    get accessIcon() { return this.selectedUser?.hasFonadaAccess ? 'utility:success' : 'utility:warning'; }
    get accessClass() { return this.selectedUser?.hasFonadaAccess ? 'slds-theme_success' : 'slds-theme_warning'; }
    get credLabel() { return this.selectedUser?.hasCredentialRead ? 'Credential read: yes' : 'Credential read: missing'; }
    get credIcon() { return this.selectedUser?.hasCredentialRead ? 'utility:success' : 'utility:warning'; }
    get credClass() { return `slds-m-left_x-small ${this.selectedUser?.hasCredentialRead ? 'slds-theme_success' : 'slds-theme_warning'}`; }
    get copyLabel() { return this.copied ? 'Copied ✓' : 'Copy script'; }

    async handleSelect(event) {
        this.selected = event.detail.value;
        try {
            await this.refreshScript();
        } catch (e) {
            this.error = this.message(e);
        }
    }

    handleRefresh() {
        this.load();
    }

    async handleCopy() {
        try {
            await navigator.clipboard.writeText(this.script);
            this.copied = true;
        } catch {
            // Fallback: select the text so the user can press Ctrl+C.
            const box = this.template.querySelector('.script-box');
            if (box) { box.focus(); box.select(); }
            this.error = 'Your browser blocked the clipboard. Click in the script box, press Ctrl+A then Ctrl+C.';
        }
    }

    handleDownload() {
        const link = document.createElement('a');
        link.href = 'data:text/plain;charset=utf-8,' + encodeURIComponent(this.script);
        link.download = 'Fonada_MCP_Agent.agent';
        link.click();
    }

    async handleFixAccess() {
        this.adminMessage = undefined;
        try {
            const n = await grantAgentAccess();
            this.adminMessage = `Access granted to ${n} agent user(s). It can take up to a minute to apply.`;
            await this.load();
        } catch (e) {
            this.adminMessage = this.message(e);
        }
    }

    async handlePrepareUninstall() {
        this.adminMessage = undefined;
        const ok = await LightningConfirm.open({
            message: 'This removes every assignment of "Fonada MCP - Permission Set" and deletes the "Fonada MCP - '
                + 'Agent Credential Read" permission set. Your Fonada agent stops working until access is granted again. Continue?',
            variant: 'header',
            label: 'Prepare Fonada MCP for uninstall',
            theme: 'warning'
        });
        if (!ok) return;
        try {
            const n = await prepareUninstall();
            this.adminMessage = `Removed ${n} permission set assignment(s). Now delete the Fonada agent, then uninstall `
                + 'from Setup → Installed Packages.';
            await this.load();
        } catch (e) {
            this.adminMessage = this.message(e);
        }
    }

    message(e) {
        return e?.body?.message || e?.message || 'Something went wrong.';
    }
}
