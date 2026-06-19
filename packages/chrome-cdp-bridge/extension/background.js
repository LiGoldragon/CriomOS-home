// CriomOS CDP Bridge — extension service worker.
//
// Attaches the chrome.debugger API to the tab the human clicks (the supervised
// consent gesture, Spirit 7hmc) and relays that tab's raw Chrome DevTools
// Protocol over an outbound WebSocket to the local relay (relay.mjs). Because
// chrome.debugger attaches FROM INSIDE the browser on the real profile, this
// bridges the human's actual logged-in Chrome (Spirit 5g4d) without the
// external --remote-debugging-port that Chrome 136+ refuses on the default
// profile.
//
// Exactly ONE tab is bridged at a time. Click the toolbar icon to attach the
// active tab; click again (on the attached tab) to detach. Closing the relay or
// the tab also detaches. The extension only relays CDP for the consented tab;
// it never opens new tabs or touches other tabs.

const RELAY_HOST = '127.0.0.1';
const RELAY_PORT = 9333;

let socket = null;
let attachedTabId = null;
const PROTOCOL_VERSION = '1.3';

async function getToken() {
  // The relay token is seeded into chrome.storage.local by the operator (the
  // status page / one-time setup). Empty => loopback-only, no token.
  const { bridgeToken } = await chrome.storage.local.get('bridgeToken');
  return bridgeToken || '';
}

function relayUrl(token) {
  const q = token ? `?token=${encodeURIComponent(token)}` : '';
  return `ws://${RELAY_HOST}:${RELAY_PORT}/extension${q}`;
}

function setBadge(text, color) {
  chrome.action.setBadgeText({ text });
  if (color) chrome.action.setBadgeBackgroundColor({ color });
}

async function tabInfo(tabId) {
  try {
    const tab = await chrome.tabs.get(tabId);
    return { url: tab.url || 'about:blank', title: tab.title || '' };
  } catch {
    return { url: 'about:blank', title: '' };
  }
}

async function attach(tabId) {
  const debuggee = { tabId };
  await chrome.debugger.attach(debuggee, PROTOCOL_VERSION);
  attachedTabId = tabId;

  const token = await getToken();
  socket = new WebSocket(relayUrl(token));

  socket.addEventListener('open', async () => {
    const info = await tabInfo(tabId);
    socket.send(
      JSON.stringify({ bridge: 'attached', targetId: `tab-${tabId}`, ...info }),
    );
    setBadge('ON', '#2e7d32');
  });

  // Relay -> tab: forward CDP commands to chrome.debugger.
  socket.addEventListener('message', async (event) => {
    let object;
    try {
      object = JSON.parse(event.data);
    } catch {
      return;
    }
    const { id, method, params } = object;
    if (!method) return;
    try {
      const result = await chrome.debugger.sendCommand(
        { tabId },
        method,
        params || {},
      );
      if (id) socket.send(JSON.stringify({ id, result: result || {} }));
    } catch (error) {
      if (id) {
        socket.send(
          JSON.stringify({
            id,
            error: { code: -32000, message: String(error && error.message) },
          }),
        );
      }
    }
  });

  socket.addEventListener('close', () => detach('relay-closed'));
  socket.addEventListener('error', () => detach('relay-error'));
}

// tab -> relay: forward CDP events emitted by the attached tab.
chrome.debugger.onEvent.addListener((source, method, params) => {
  if (source.tabId !== attachedTabId || !socket) return;
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify({ method, params }));
  }
});

chrome.debugger.onDetach.addListener((source) => {
  if (source.tabId === attachedTabId) detach('debugger-detached');
});

async function detach(reason) {
  const tabId = attachedTabId;
  attachedTabId = null;
  try {
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify({ bridge: 'detached', reason }));
    }
  } catch {}
  try {
    if (socket) socket.close();
  } catch {}
  socket = null;
  try {
    if (tabId != null) await chrome.debugger.detach({ tabId });
  } catch {}
  setBadge('', null);
}

// Toolbar click: attach the clicked tab, or detach if it is already attached.
chrome.action.onClicked.addListener(async (tab) => {
  if (!tab || tab.id == null) return;
  if (attachedTabId === tab.id) {
    await detach('user-click');
    return;
  }
  if (attachedTabId != null) await detach('switch');
  try {
    await attach(tab.id);
  } catch (error) {
    setBadge('ERR', '#c62828');
  }
});
