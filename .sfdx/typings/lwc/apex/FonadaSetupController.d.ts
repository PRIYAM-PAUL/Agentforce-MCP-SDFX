declare module "@salesforce/apex/FonadaSetupController.getAgentUsers" {
  export default function getAgentUsers(): Promise<any>;
}
declare module "@salesforce/apex/FonadaSetupController.buildScript" {
  export default function buildScript(param: {username: any}): Promise<any>;
}
declare module "@salesforce/apex/FonadaSetupController.buildScriptWithModel" {
  export default function buildScriptWithModel(param: {username: any, modelKey: any}): Promise<any>;
}
declare module "@salesforce/apex/FonadaSetupController.grantAgentAccess" {
  export default function grantAgentAccess(): Promise<any>;
}
declare module "@salesforce/apex/FonadaSetupController.prepareUninstall" {
  export default function prepareUninstall(): Promise<any>;
}
