/**
 * Fonada MCP - minimal MCP client for Apex.
 *
 * Calls one Fonada MCP tool (JSON-RPC "tools/call") through the packaged named
 * credential, so multi-step work (e.g. launching a campaign) runs with an exact,
 * correctly typed payload instead of relying on the LLM to build JSON.
 * The caller must have Fonada access (the packaged permission sets), exactly
 * like the MCP tools used by the agent.
 *
 * Protocol: each call does the MCP handshake (initialize + notifications/initialized),
 * then sends tools/call with the negotiated MCP-Protocol-Version header and the
 * Mcp-Session-Id the server returned, if any. If the handshake fails for any reason
 * other than the API key, the tool call is still sent without those headers (the
 * behaviour of earlier versions), so a server-side change cannot stop campaigns.
 */
public with sharing class FonadaMcpClient {

    public class ToolResult {
        public Boolean ok = false;
        /** Text content returned by the tool (usually JSON). */
        public String text;
        /** text parsed as a JSON object, when it is one. */
        public Map<String, Object> data;
        /** Error message when ok = false. */
        public String error;
    }

    @TestVisible
    private static String endpoint() {
        String cls = FonadaMcpClient.class.getName();
        String ns = cls.contains('.') ? cls.substringBefore('.') + '__' : '';
        return 'callout:' + ns + 'FonadaMCP';
    }

    /** MCP protocol version this client asks for; the server answers with the one it supports. */
    @TestVisible private static final String CLIENT_PROTOCOL_VERSION = '2025-06-18';
    private static final Integer TOTAL_TIMEOUT_MS = 120000;     // Apex limit for all callouts in a transaction
    private static final Integer HANDSHAKE_TIMEOUT_MS = 15000;
    private static final String KEY_ERROR =
        'Fonada rejected the API key (HTTP {0}). Check the FonadaApiKey in the FonadaMCP external credential.';

    /** Result of the MCP handshake: negotiated version and session id (either may be null). */
    @TestVisible
    private class Session {
        String protocolVersion;
        String sessionId;
        Integer authStatus;     // 401/403 from initialize: the key is wrong
    }

    /** Handshake result reused by every tool call in the same transaction. */
    private static Session cachedSession;
    /** Start of the first callout in this transaction (all callouts share one 120 s budget). */
    private static Long transactionStart;

    public static ToolResult callTool(String toolName, Map<String, Object> arguments) {
        ToolResult tr = new ToolResult();
        if (transactionStart == null) transactionStart = System.currentTimeMillis();

        Session session = cachedSession != null ? cachedSession : initialize();
        if (session.authStatus != null) {
            tr.error = String.format(KEY_ERROR, new List<Object>{ String.valueOf(session.authStatus) });
            return tr;
        }
        cachedSession = session;

        Integer remaining = TOTAL_TIMEOUT_MS - (System.currentTimeMillis() - transactionStart).intValue();
        if (remaining < 2000) {
            tr.error = 'Fonada took too long to answer, so ' + toolName + ' was not sent. Try again.';
            return tr;
        }
        HttpRequest req = newRequest(session);
        req.setTimeout(Math.min(TOTAL_TIMEOUT_MS, remaining));
        req.setBody(safeBody(new Map<String, Object>{
            'jsonrpc' => '2.0',
            'id' => 1,
            'method' => 'tools/call',
            'params' => new Map<String, Object>{ 'name' => toolName, 'arguments' => arguments }
        }));

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception e) {
            tr.error = 'Could not reach Fonada: ' + e.getMessage();
            return tr;
        }
        if (res.getStatusCode() == 401 || res.getStatusCode() == 403) {
            tr.error = String.format(KEY_ERROR, new List<Object>{ String.valueOf(res.getStatusCode()) });
            return tr;
        }
        if (res.getStatusCode() >= 300) {
            tr.error = 'Fonada returned HTTP ' + res.getStatusCode() + ': ' + res.getBody().left(500);
            return tr;
        }
        return parse(res.getBody(), tr);
    }

    private static HttpRequest newRequest(Session session) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint());
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json, text/event-stream');
        if (session != null && String.isNotBlank(session.protocolVersion)) {
            req.setHeader('MCP-Protocol-Version', session.protocolVersion);
        }
        if (session != null && String.isNotBlank(session.sessionId)) {
            req.setHeader('Mcp-Session-Id', session.sessionId);
        }
        return req;
    }

    /**
     * MCP handshake: initialize, then notifications/initialized. Never throws; on any
     * failure other than 401/403 it returns an empty session so the tool call goes ahead
     * exactly as in earlier versions.
     */
    @TestVisible
    private static Session initialize() {
        Session s = new Session();
        try {
            HttpRequest init = newRequest(null);
            init.setTimeout(HANDSHAKE_TIMEOUT_MS);
            init.setBody(JSON.serialize(new Map<String, Object>{
                'jsonrpc' => '2.0',
                'id' => 0,
                'method' => 'initialize',
                'params' => new Map<String, Object>{
                    'protocolVersion' => CLIENT_PROTOCOL_VERSION,
                    'capabilities' => new Map<String, Object>(),
                    'clientInfo' => new Map<String, Object>{ 'name' => 'Fonada MCP for Agentforce', 'version' => '1' }
                }
            }));
            HttpResponse res = new Http().send(init);
            Integer code = res.getStatusCode();
            if (code == 401 || code == 403) {
                s.authStatus = code;
                return s;
            }
            if (code >= 300) return s;
            Map<String, Object> rpc = findRpcMessage(res.getBody());
            Object result = rpc == null ? null : rpc.get('result');
            if (!(result instanceof Map<String, Object>)) return s;
            Object version = ((Map<String, Object>) result).get('protocolVersion');
            if (version instanceof String && ((String) version).length() <= 20) s.protocolVersion = (String) version;
            String sid = res.getHeader('Mcp-Session-Id');
            if (String.isNotBlank(sid) && sid.length() <= 200) s.sessionId = sid;

            HttpRequest done = newRequest(s);
            done.setTimeout(HANDSHAKE_TIMEOUT_MS);
            done.setBody(JSON.serialize(new Map<String, Object>{
                'jsonrpc' => '2.0', 'method' => 'notifications/initialized'
            }));
            new Http().send(done);   // 202 expected; the result does not matter
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'FonadaMCP: MCP handshake skipped: ' + e.getMessage());
        }
        return s;
    }

    /**
     * Serialises the JSON-RPC request. The named credential evaluates merge fields,
     * so "{!" coming from user or CRM text is neutralised: no Salesforce formula
     * (for example the API key) can ever be expanded inside the request body.
     * "{!" can only occur inside JSON string values, so the payload stays valid.
     */
    @TestVisible
    private static String safeBody(Map<String, Object> payload) {
        return JSON.serialize(payload).replace('{!', '{ !');
    }

    /**
     * Parses a JSON-RPC response. The body may be plain JSON or Server-Sent Events
     * with one or more "data:" frames (e.g. progress notifications before the
     * result); the frame carrying "result" or "error" is used.
     */
    @TestVisible
    private static ToolResult parse(String body, ToolResult tr) {
        Map<String, Object> rpc = findRpcMessage(body);
        if (rpc == null) {
            tr.error = 'Unexpected response from Fonada: ' + (body == null ? '' : body.left(300));
            return tr;
        }
        if (rpc.get('error') != null) {
            Map<String, Object> err = (Map<String, Object>) rpc.get('error');
            tr.error = String.valueOf(err.get('message'));
            return tr;
        }
        Map<String, Object> result = (Map<String, Object>) rpc.get('result');
        List<String> texts = new List<String>();
        if (result != null && result.get('content') instanceof List<Object>) {
            for (Object c : (List<Object>) result.get('content')) {
                Map<String, Object> part = (Map<String, Object>) c;
                if (part.get('text') != null) texts.add(String.valueOf(part.get('text')));
            }
        }
        tr.text = String.join(texts, '\n');
        try {
            Object parsed = JSON.deserializeUntyped(tr.text);
            if (parsed instanceof Map<String, Object>) tr.data = (Map<String, Object>) parsed;
        } catch (Exception e) {
            tr.data = null;   // plain-text result
        }
        Boolean isError = result != null && result.get('isError') == true;
        tr.ok = !isError;
        if (isError) tr.error = String.isBlank(tr.text) ? 'The Fonada tool reported an error.' : tr.text.left(1000);
        return tr;
    }

    /** Returns the JSON-RPC response object (with result or error) from plain JSON or SSE frames. */
    private static Map<String, Object> findRpcMessage(String body) {
        if (String.isBlank(body)) return null;
        List<String> candidates = new List<String>();
        for (String line : body.split('\\r?\\n')) {
            String t = line.trim();
            if (t.startsWith('data:')) candidates.add(t.substring(5).trim());
        }
        candidates.add(body.trim());                       // plain JSON body
        Integer first = body.indexOf('{');
        Integer last = body.lastIndexOf('}');
        if (first >= 0 && last > first) candidates.add(body.substring(first, last + 1));
        for (String c : candidates) {
            if (!c.startsWith('{')) continue;
            try {
                Object parsed = JSON.deserializeUntyped(c);
                if (parsed instanceof Map<String, Object>) {
                    Map<String, Object> m = (Map<String, Object>) parsed;
                    if (m.containsKey('result') || m.containsKey('error')) return m;
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.FINEST, 'FonadaMCP: response frame is not JSON, trying the next one');
            }
        }
        return null;
    }
}
