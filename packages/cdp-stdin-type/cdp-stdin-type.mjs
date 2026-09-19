// cdp-stdin-type — deliver text from STDIN into the focused element of a
// remote Chrome tab over the Chrome DevTools Protocol, without the text ever
// touching argv, the environment, a file, or a log line.
//
// WHY this exists: the living signs in to their OWN accounts (Claude, ChatGPT)
// in a browser running on a rented server. The password lives in gopass on
// their own laptop and must never be stored on that server nor seen by an
// agent. The workspace secrets discipline says: pipe the producer straight into
// the consumer's stdin, nothing in argv/env/files/logs. Browsers have no such
// stdin interface — so this tool IS that interface. It is the consumer:
//
//   gopass show -o accounts/anthropic | ssh server cdp-stdin-type \
//     --endpoint http://127.0.0.1:9223 --url-contains claude.ai --submit
//
// The bytes go stdin -> CDP `Input.insertText` -> the page's focused field.
// Nothing here prints, stores, or re-derives them. The unavoidable boundaries
// are named honestly in the package's default.nix and in the witness: the
// kernel pipe, the SSH transport, and Chrome's own process memory all still see
// the plaintext, as they must for the human to be signed in at all.
//
// Deliberately dependency-free: node 22 ships a global WebSocket, so the whole
// CDP client is a few dozen lines below and the Nix package needs no npm tree.

const USAGE = `usage: cdp-stdin-type --endpoint http://127.0.0.1:9223
                     [--target <id> | --url-contains <substring>]
                     [--submit] [--timeout <ms>]

Reads text from stdin (one trailing newline stripped) and types it into the
currently focused element of the chosen page target. Refuses to run on a TTY.
Never prints the text.`;

function fail(message) {
  process.stderr.write(`cdp-stdin-type: ${message}\n`);
  process.exit(1);
}

// ---- arguments -------------------------------------------------------------

function parseArguments(argv) {
  const options = {
    endpoint: 'http://127.0.0.1:9223',
    target: null,
    urlContains: null,
    submit: false,
    timeout: 15000,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    const value = () => {
      const next = argv[index + 1];
      if (next === undefined) fail(`${flag} needs a value`);
      index += 1;
      return next;
    };
    switch (flag) {
      case '--endpoint':
        options.endpoint = value();
        break;
      case '--target':
        options.target = value();
        break;
      case '--url-contains':
        options.urlContains = value();
        break;
      case '--submit':
        options.submit = true;
        break;
      case '--timeout':
        options.timeout = Number(value());
        if (!Number.isFinite(options.timeout) || options.timeout <= 0) {
          fail('--timeout needs a positive number of milliseconds');
        }
        break;
      case '--help':
      case '-h':
        process.stdout.write(`${USAGE}\n`);
        process.exit(0);
        break;
      default:
        fail(`unknown argument ${flag}\n${USAGE}`);
    }
  }
  if (options.target && options.urlContains) {
    fail('--target and --url-contains are mutually exclusive');
  }
  return options;
}

// ---- stdin -----------------------------------------------------------------

// Read stdin whole. The result is returned to exactly one caller and is never
// logged, echoed, or put anywhere addressable by another process.
async function readStdin() {
  if (process.stdin.isTTY) {
    fail(
      'stdin is a TTY. Pipe the text in (e.g. gopass show -o <path> | cdp-stdin-type ...); ' +
        'this tool never prompts, so a secret cannot be typed where it would be echoed.',
    );
  }
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  let text = Buffer.concat(chunks).toString('utf8');
  // Strip exactly ONE trailing newline (the shell/gopass line terminator),
  // and the CR of a CRLF pair with it. Any further newlines are the payload.
  if (text.endsWith('\n')) text = text.slice(0, -1);
  if (text.endsWith('\r')) text = text.slice(0, -1);
  return text;
}

// ---- CDP -------------------------------------------------------------------

async function listPageTargets(endpoint) {
  const base = endpoint.replace(/\/+$/, '');
  let response;
  try {
    response = await fetch(`${base}/json/list`);
  } catch (error) {
    fail(`cannot reach the CDP endpoint at ${base}: ${error.message}`);
  }
  if (!response.ok) fail(`CDP endpoint ${base}/json/list returned ${response.status}`);
  const targets = await response.json();
  return targets.filter((target) => target.type === 'page');
}

function chooseTarget(targets, options) {
  if (targets.length === 0) fail('no page targets on that endpoint');
  if (options.target) {
    const chosen = targets.find((target) => target.id === options.target);
    if (!chosen) fail(`no page target with id ${options.target}`);
    return chosen;
  }
  if (options.urlContains) {
    const matches = targets.filter(
      (target) => typeof target.url === 'string' && target.url.includes(options.urlContains),
    );
    if (matches.length === 0) fail(`no page target whose url contains ${options.urlContains}`);
    if (matches.length > 1) {
      fail(
        `${matches.length} page targets match ${options.urlContains}; ` +
          'disambiguate with --target <id>',
      );
    }
    return matches[0];
  }
  if (targets.length > 1) {
    fail(
      `${targets.length} page targets are open; choose one with --url-contains or --target <id>`,
    );
  }
  return targets[0];
}

// Minimal CDP session over the page's webSocketDebuggerUrl.
function openSession(webSocketDebuggerUrl, timeout) {
  const socket = new WebSocket(webSocketDebuggerUrl);
  const pending = new Map();
  let nextId = 1;
  let closedReason = null;

  const ready = new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timed out connecting to the page target')), timeout);
    socket.addEventListener('open', () => {
      clearTimeout(timer);
      resolve();
    });
    socket.addEventListener('error', () => {
      clearTimeout(timer);
      reject(new Error('websocket error connecting to the page target'));
    });
  });

  socket.addEventListener('message', (event) => {
    let message;
    try {
      message = JSON.parse(event.data);
    } catch {
      return;
    }
    const entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id);
    if (message.error) entry.reject(new Error(message.error.message || 'CDP error'));
    else entry.resolve(message.result);
  });

  socket.addEventListener('close', () => {
    closedReason = closedReason || 'the page target closed the connection';
    for (const entry of pending.values()) entry.reject(new Error(closedReason));
    pending.clear();
  });

  function send(method, params) {
    const id = nextId;
    nextId += 1;
    return new Promise((resolve, reject) => {
      if (socket.readyState !== WebSocket.OPEN) {
        reject(new Error(closedReason || 'websocket is not open'));
        return;
      }
      const timer = setTimeout(() => {
        pending.delete(id);
        reject(new Error(`CDP ${method} timed out`));
      }, timeout);
      pending.set(id, {
        resolve: (result) => {
          clearTimeout(timer);
          resolve(result);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        },
      });
      socket.send(JSON.stringify({ id, method, params: params || {} }));
    });
  }

  return { ready, send, close: () => socket.close() };
}

// Enter, as a browser sees it: keyDown then keyUp with the same descriptor.
async function pressEnter(session) {
  const key = {
    key: 'Enter',
    code: 'Enter',
    windowsVirtualKeyCode: 13,
    nativeVirtualKeyCode: 13,
    text: '\r',
    unmodifiedText: '\r',
  };
  await session.send('Input.dispatchKeyEvent', { type: 'keyDown', ...key });
  await session.send('Input.dispatchKeyEvent', { type: 'keyUp', ...key });
}

// ---- main ------------------------------------------------------------------

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const text = await readStdin();
  if (text.length === 0) fail('stdin was empty; nothing to type');

  // From here on `text` is live. Any thrown message is scrubbed before it can
  // reach stderr, so an unlucky error string can never carry the secret out.
  const scrub = (message) => String(message).split(text).join('<redacted>');

  const targets = await listPageTargets(options.endpoint);
  const target = chooseTarget(targets, options);
  const session = openSession(target.webSocketDebuggerUrl, options.timeout);

  try {
    await session.ready;
    // Input.insertText delivers the whole string to the focused element as an
    // IME-style commit: one CDP message, no per-character key events, no
    // keylogger-shaped trail, and no dependence on the keyboard layout.
    await session.send('Input.insertText', { text });
    if (options.submit) await pressEnter(session);
  } catch (error) {
    session.close();
    fail(scrub(error.message));
  }
  session.close();

  // Structural output only: what was driven, never what was typed — not even
  // its length, which for a password is itself worth withholding.
  process.stdout.write(`target ${target.id}\n`);
  process.stdout.write(`url ${target.url}\n`);
  process.stdout.write(
    `ok: delivered stdin to the focused element${options.submit ? ' and pressed Enter' : ''}\n`,
  );
}

main().catch((error) => fail(error && error.message ? error.message : String(error)));
