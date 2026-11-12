/**
 * Fonada MCP: when an Agentforce agent user is created, re-activated or moved to a
 * new profile, grant it Fonada MCP access asynchronously (see FonadaMCPAgentAccess).
 * Only agent users queue a job; changes to ordinary users cost one Profile query.
 */
trigger FonadaMCPAgentUserTrigger on User (after insert, after update) {
    FonadaMCPAgentAccess.onUserChange(Trigger.new, Trigger.oldMap);
}
