// chrome-cdp-bridge relay — exposes a browser-level CDP endpoint backed by a
// chrome.debugger extension attached to the REAL Chrome profile.
//
// WHY this exists: Chrome 136+ refuses the external --remote-debugging-port on
// the default user-data-dir, so a CDP client (browser-use) cannot attach to the
// human's real, logged-in Chrome the normal way. A Chrome extension using the
// chrome.debugger API CAN attach to a tab FROM INSIDE the browser, on the real
// profile (Spirit 5g4d). This relay is the meeting point: the extension dials in
// over a WebSocket and proxies raw CDP frames for the attached tab; the relay
// re-publishes a browser-LEVEL CDP endpoint (/json/version + a browser
// webSocketDebuggerUrl) that browser-use targets via --cdp-url.
//
// The load-bearing subtlety (the reason naive extension relays fail with
// "Target.attachToBrowserTarget: Not allowed"): browser-use 0.13.x connects to
// the CDP url as a BROWSER target and immediately drives the Target domain
// (setAutoAttach, getTargets, attachToTarget, createTarget). chrome.debugger is
// TAB-level and exposes none of those at the browser level. So the relay
// SYNTHESISES the browser-level Target domain over the single attached tab:
// it answers those methods itself and only forwards page/runtime/dom CDP to the
// extension. This mirrors what the official Playwright extension does
// internally; here it is a standalone, dependency-light relay.
//
// Scope is deliberately ONE attached tab (the supervised-scout discipline,
// Spirit 7hmc): the human clicks the extension on the tab they consent to
// expose; the relay presents exactly that tab as the sole page target.

import http from 'node:http';
import crypto from 'node:crypto';
import { WebSocketServer, WebSocket } from 'ws';

const HOST = process.env.CHROME_CDP_BRIDGE_HOST || '127.0.0.1';
const PORT = Number(process.env.CHROME_CDP_BRIDGE_PORT || 9333);
// Shared token: the extension must present it to dial in, and (optionally) the
// CDP client to connect. Never logged. Sourced from gopass by the wrapper.
const TOKEN = process.env.CHROME_CDP_BRIDGE_TOKEN || '';
// Stable synthetic browser-target id (only meaningful inside this relay).
const BROWSER_TARGET_ID = 'bridge-browser';
const BROWSER_SESSION_ID = 'bridge-browser-session';

// One bridged tab at a time. State for the currently attached page target.
const state = {
  extension: null, // ws from the extension service worker
  client: null, // ws from the CDP client (browser-use)
  pageTargetId: null, // chrome.debugger tab target id, reported by the extension
  pageSessionId: null, // synthetic flat session id for the page target
  pageUrl: 'about:blank',
  pageTitle: '',
  autoAttach: false, // did the client enable Target.setAutoAttach?
};

function log(...parts) {
  // Structural logs only. Never print the token or page content.
  process.stderr.write(`[chrome-cdp-bridge] ${parts.join(' ')}\n`);
}

function send(ws, object) {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(object));
}

function newPageSessionId() {
  return 'page-' + crypto.randomBytes(8).toString('hex');
}

// Build the Target.targetInfo for the single bridged page.
function pageTargetInfo() {
  return {
    targetId: state.pageTargetId || 'bridge-page',
    type: 'page',
    title: state.pageTitle || '',
    url: state.pageUrl || 'about:blank',
    attached: Boolean(state.pageSessionId),
    canAccessOpener: false,
    browserContextId: 'bridge-default-context',
  };
}

// Emit Target.attachedToTarget to the client so its session manager picks up
// the page as a flat session (waitForDebuggerOnStart=false).
function announcePageAttached() {
  if (!state.pageSessionId) state.pageSessionId = newPageSessionId();
  send(state.client, {
    method: 'Target.attachedToTarget',
    params: {
      sessionId: state.pageSessionId,
      targetInfo: pageTargetInfo(),
      waitingForDebugger: false,
    },
  });
}

// ---- Browser-level CDP methods the relay answers itself (never forwarded) ----
// These are the methods browser-use sends at the browser level; chrome.debugger
// cannot serve them, so the relay emulates them over the single attached tab.
function handleBrowserLevelMethod(id, method, params) {
  switch (method) {
    case 'Target.setAutoAttach': {
      state.autoAttach = Boolean(params && params.autoAttach);
      // Ack, then (if a page is attached) announce it so the client attaches.
      send(state.client, { id, result: {} });
      if (state.autoAttach && state.pageTargetId) announcePageAttached();
      return true;
    }
    case 'Target.getTargets': {
      const targetInfos = state.pageTargetId ? [pageTargetInfo()] : [];
      send(state.client, { id, result: { targetInfos } });
      return true;
    }
    case 'Target.getTargetInfo': {
      send(state.client, { id, result: { targetInfo: pageTargetInfo() } });
      return true;
    }
    case 'Target.getBrowserContexts': {
      send(state.client, {
        id,
        result: { browserContextIds: ['bridge-default-context'] },
      });
      return true;
    }
    case 'Target.attachToTarget': {
      // Client explicitly attaches to the page target.
      if (!state.pageSessionId) state.pageSessionId = newPageSessionId();
      send(state.client, { id, result: { sessionId: state.pageSessionId } });
      announcePageAttached();
      return true;
    }
    case 'Target.attachToBrowserTarget': {
      send(state.client, {
        id,
        result: { sessionId: BROWSER_SESSION_ID },
      });
      return true;
    }
    case 'Target.createTarget': {
      // The supervised-scout bridge exposes exactly the one consented tab; it
      // does not spawn new browser tabs on the human's real profile. Return the
      // existing attached page as the "created" target so the client drives it
      // (the client issues its own Page.navigate next — don't navigate here, or
      // a double-navigate races the client's lifecycle wait), then announce it.
      send(state.client, {
        id,
        result: { targetId: state.pageTargetId || 'bridge-page' },
      });
      announcePageAttached();
      return true;
    }
    case 'Target.setDiscoverTargets': {
      send(state.client, { id, result: {} });
      if (params && params.discover && state.pageTargetId) {
        send(state.client, {
          method: 'Target.targetCreated',
          params: { targetInfo: pageTargetInfo() },
        });
      }
      return true;
    }
    case 'Target.closeTarget': {
      // Never close the human's tab from the bridge; report success no-op.
      send(state.client, { id, result: { success: true } });
      return true;
    }
    case 'Browser.getVersion': {
      send(state.client, {
        id,
        result: {
          protocolVersion: '1.3',
          product: 'ChromeCdpBridge/real-profile',
          revision: '@bridge',
          userAgent: 'chrome-cdp-bridge',
          jsVersion: '0',
        },
      });
      return true;
    }
    default:
      return false; // not a browser-level method we own
  }
}

// Forward a CDP message to the extension (page-level commands).
function forwardToExtension(object) {
  send(state.extension, object);
}

// ---- Client (browser-use) -> relay ----
function onClientMessage(raw) {
  let object;
  try {
    object = JSON.parse(raw);
  } catch {
    return;
  }
  const { id, method, params, sessionId } = object;

  // No sessionId (or the synthetic browser session) => browser-level command.
  const browserLevel = !sessionId || sessionId === BROWSER_SESSION_ID;
  if (browserLevel && handleBrowserLevelMethod(id, method, params)) return;

  // Page-level command: forward to the extension to run via chrome.debugger.
  // chrome.debugger.sendCommand is already tab-scoped, so strip the synthetic
  // session id — the extension runs the bare {method, params} on the attached
  // tab and echoes back the id. (Track the id so the response can be routed.)
  if (!state.extension) {
    send(state.client, {
      id,
      error: { code: -32000, message: 'no tab attached to the bridge yet' },
    });
    return;
  }
  pendingClientIds.add(id);
  forwardToExtension({ id, method, params });
}

// Ids the client is awaiting; their responses get the page session id back.
const pendingClientIds = new Set();

// ---- Extension -> relay ----
function onExtensionMessage(raw) {
  let object;
  try {
    object = JSON.parse(raw);
  } catch {
    return;
  }

  // Control frames from the extension service worker.
  if (object.bridge === 'attached') {
    state.pageTargetId = object.targetId || 'bridge-page';
    state.pageUrl = object.url || 'about:blank';
    state.pageTitle = object.title || '';
    log('extension attached tab', state.pageTargetId);
    if (state.client && (state.autoAttach || true)) announcePageAttached();
    return;
  }
  if (object.bridge === 'detached') {
    log('extension detached tab');
    state.pageTargetId = null;
    state.pageSessionId = null;
    return;
  }
  if (object.bridge === 'info') {
    state.pageUrl = object.url || state.pageUrl;
    state.pageTitle = object.title || state.pageTitle;
    return;
  }

  // Plain CDP responses/events from the attached tab. browser-use sent its
  // page commands on the synthetic page session and expects the matching
  // session id on responses and events, so reattach it.
  if (state.pageSessionId) {
    if (object.id !== undefined && pendingClientIds.has(object.id)) {
      pendingClientIds.delete(object.id);
      object.sessionId = state.pageSessionId;
    } else if (object.method !== undefined && object.sessionId === undefined) {
      object.sessionId = state.pageSessionId;
    }
  }
  send(state.client, object);
}

// Constant-time token compare.
function tokenOk(provided) {
  if (!TOKEN) return true; // no token configured -> open (loopback only)
  const a = Buffer.from(String(provided || ''));
  const b = Buffer.from(TOKEN);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  // CDP discovery endpoint: browser-use --cdp-url http://HOST:PORT fetches this.
  if (url.pathname === '/json/version') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(
      JSON.stringify({
        Browser: 'ChromeCdpBridge/real-profile',
        'Protocol-Version': '1.3',
        webSocketDebuggerUrl: `ws://${HOST}:${PORT}/devtools/browser/${BROWSER_TARGET_ID}`,
      }),
    );
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server });
wss.on('connection', (ws, req) => {
  const url = new URL(req.url, `http://${HOST}:${PORT}`);
  const token = url.searchParams.get('token');

  if (url.pathname === '/extension') {
    if (!tokenOk(token)) {
      log('extension rejected: bad token');
      ws.close(1008, 'bad token');
      return;
    }
    state.extension = ws;
    log('extension connected');
    ws.on('message', onExtensionMessage);
    ws.on('close', () => {
      if (state.extension === ws) {
        state.extension = null;
        state.pageTargetId = null;
        state.pageSessionId = null;
      }
      log('extension disconnected');
    });
    return;
  }

  // Browser-level CDP client endpoint (ws://.../devtools/browser/<id>).
  if (url.pathname.startsWith('/devtools/browser/')) {
    if (!tokenOk(token)) {
      log('client rejected: bad token');
      ws.close(1008, 'bad token');
      return;
    }
    state.client = ws;
    log('cdp client connected');
    ws.on('message', onClientMessage);
    ws.on('close', () => {
      if (state.client === ws) state.client = null;
      log('cdp client disconnected');
    });
    return;
  }

  ws.close(1008, 'unknown path');
});

server.listen(PORT, HOST, () => {
  log(`relay listening on http://${HOST}:${PORT}`);
  log(`cdp-url for browser-use:  http://${HOST}:${PORT}`);
  log('waiting for the extension to attach a tab (click the toolbar icon)');
});
