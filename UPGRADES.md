# Upgrades

## Orchestrate 0.26.0 WireContract cutover

This Home generation pins Orchestrate commit
`dadd537bbd2ed2ffc5260fffc5735f9f020cc774` (0.26.0). It is a coordinated
breaking ordinary and meta socket replacement: ordinary frames are generated
WireContract `1/6` frames and privileged frames are `2/5` frames. Install the
Nexus and both client wrappers as one Home generation; no legacy envelope,
parser, or text compatibility path remains.

Before activation, verify the target user, source revision, and Lojix
transport identify the same deployment target. The 0.25 Nexus must be stopped
before the read-only candidate can open its existing Sema store. Run
`orchestrate-upgrade-preflight` with the same XDG state and runtime roots as
the service, and proceed only on `active legacy PathLock rows: 0`. A running
0.25 process correctly makes this preflight fail with its database lock held;
that is not permission to bypass the preflight.

The schema version, Sema families, hashes, configuration, complete Lock facts,
and ID allocator are unchanged. Keep
`$XDG_STATE_HOME/orchestrate-nexus/orchestrate-nexus.sema` in place. Do not
move or import the retired `$XDG_STATE_HOME/orchestrate/` store. After the
declarative Home activation, verify both sockets, `Observe.Locks`, a complete
Lock, the typed duplicate-name refusal, and Release by returned ID. Verify the
meta Configure reply separately; a configuration change still binds only on a
later restart.

For rollback, activate the previously pinned 0.25 Home generation as one
generation, including its matching ordinary and meta wrappers. The durable
schema is shared, so no data conversion or store restore is needed. Do not
mix a 0.25 client with a 0.26 Nexus (or conversely), and do not roll back if a
subsequent release has changed the declared Sema schema without a separately
approved migration review.

## Agent Intercom service-gate removal

This generation removes the two retired Agent Intercom node-service gates.
Agent Intercom wrappers, Pi adapters, MCP registration, and OpenCode plugins
are now available in every Home profile, while ordinary `codex` and `claude`
remain separately owned by their canonical pinned packages. There is no
compatibility service declaration to retain or migrate.

Desktop-app support is independently selected only when the projected node
behaves as Edge, the user has cumulative medium capability, and the package
is actually available for the target platform. There is no shared
architecture gate. Keep the Horizon producer and the CriomOS consumer on
their matching removal revisions before activating this Home generation. A
non-Edge or minimum-only profile deliberately receives no Claude/ChatGPT
Desktop handlers; `codex-remote-control` remains a minimum profile service.

## Unified Codex app-server clients

This generation makes the per-user `codex-remote-control` service the only
normal Codex thread writer. Terminal `codex`, ChatGPT Desktop, and the phone
are clients of its control socket. ChatGPT Desktop reaches it only through its
packaged bare `app-server` stdio endpoint, which transparently proxies to the
existing per-user socket; it cannot start a second owner. Closing a terminal or
Desktop window detaches that client; it must not be used to stop the service.

Before activating, stop any manually started Codex app-server process. After
activation, confirm `systemctl --user is-active codex-remote-control` and run
`codex app-server daemon version`. If either fails, Desktop fails closed rather
than falling back to a bundled or host Codex writer. Repair the managed unit or
its pinned package, then restart the unit; do not start a second app-server.

`direct-codex` is the explicit raw recovery escape. It bypasses the normal
client-routing guard and can create a separate writer, so use it only to repair
or diagnose a failed managed service. It is not a normal terminal entry point.
Ordinary `codex remote-control …` now exits 126 for the same reason; it cannot
start an ephemeral private owner beside the managed socket.

The packaged checks exercise the gate, its actual Electron `resources/codex`
path, the native-mode launch environment, and daemon WebSocket reconnects. They
do not yet drive the Electron GUI through a graphical Desktop connection; that
final GUI-native smoke remains a deployment-time observation boundary.

## Persistent Claude Remote Control

Every enabled minimum Home profile now requires an explicit, absolute non-home
`criomos.claudeRemoteControl.workingDirectory` before it creates the persistent
`claude-remote-control` service. It uses `--spawn=same-dir`; the consumer's
per-user projection owns the working root and may select the `worktree` or
`session` spawn mode without baking a machine-specific path into Home. Closing
Claude Desktop or the browser/mobile client must not stop the service.

Claude Desktop, browser, and mobile operate through Anthropic's authenticated
relay. The local terminal has no supported thin-client attachment to this
owner, and normal Claude TUI launches deliberately do not set
`remoteControlAtStartup`. This change adds no Home-managed listener, tunnel,
or relay credentials.

## Orchestrate 0.25.0 Lock contract

This is a breaking ordinary-socket cutover from `PathLock` registration to
`Lock`, `Release.{id}`, and `Observe.Locks`. Before activating the Home
generation, stop the 0.24 Nexus and release every active legacy PathLock with
the 0.24 client.

Run the zero-argument, read-only candidate against the same XDG roots used by
the per-user Nexus:

```text
orchestrate-upgrade-preflight
```

Proceed only when it prints `active legacy PathLock rows: 0`. A nonzero result
means start the 0.24 Nexus, release its active legacy PathLocks, stop it, and
run the candidate again. The 0.25 Nexus checks the same condition at startup;
it does not migrate old rows or infer their Flow attribution.

After the new Nexus starts, use the wrapper with `Lock.{name flow
[/absolute/path] reason}`, confirm the complete `Locked` reply, observe it with
`Observe.Locks`, and release it by the returned integer ID. The wrapper fallback
and unconditional zero-argument service shape remain unchanged.

## Orchestrate Nexus

Home starts `orchestrate-nexus` for every user. The retired
`orchestrate-daemon` service, its PersonaDevelopment gate, its seven-argument
startup contract, and the `PERSONA_ORCHESTRATE_*` client variables are removed.

The Nexus starts with its built-in default configuration. Home provides no
bootstrap writer, frame, or configuration file. Its client wrappers set
`ORCHESTRATE_SOCKET` and `ORCHESTRATE_META_SOCKET` to the standard user runtime
paths.

The Nexus uses `$XDG_STATE_HOME/orchestrate-nexus/orchestrate-nexus.sema`. The
legacy `$XDG_STATE_HOME/orchestrate/orchestrate.sema` store is deliberately
left in place and is neither opened nor migrated.
