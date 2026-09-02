# Upgrades

## Flow identity helper

After activating a generation pinned to `harness`'s `flow-id`, a parent flow claims its lane with `flow-id codex --flows-root /absolute/flows-root` or `flow-id claude --flows-root /absolute/flows-root --parent-session UUID` before writing its first artifact.

Codex starts from normalized UUID characters `[23:29]`; Claude accepts only a canonical lowercase RFC 4122 UUIDv4 parent session and starts from its first six literal hexadecimal characters. The alias is `FLOW_ID`; its lane is `FLOW_DIRECTORY`. Existing unmarked lanes remain collisions and are never overwritten. Child threads receive those parent values and do not claim lanes.

Claude callers with non-v4 or noncanonical parent IDs must provide the authoritative canonical UUIDv4 parent session. The Home wrapper does not infer or fall back to a Claude environment variable.

The current `harness` pin publishes each versioned marker only after complete
private metadata is ready under a stable private claim lock. A concurrent
parent claim therefore cannot read a partial marker; malformed markers still
fail closed.

## Chroma 0.3.1 Datomic configuration cutover

This generation pins Chroma `0.3.1` at
`1b626d9dc325459be6c825d0c5a59a7d245d1edd`. Chroma now reads only the
schema-authored, positional `$XDG_CONFIG_HOME/chroma/config.datom`; the
legacy `config.dotos` is removed during Home activation. The Home module
projects the same concerns, palettes, adapters, template paths, Pi control,
font size, schedules, and defaults into the current Datomic `Config` anatomy.
The legacy solar labels are projected to their typed minute values: extremely
early/very early/early/on time/late/very late/extremely late become
`-120/-60/-30/0/30/60/120`.

Activate the complete Home generation. Do not run a pre-0.3 Chroma daemon
against `config.datom`, and do not retain or manually convert a Dotos config:
the declarative Home source owns the canonical file and removes the obsolete
one. A rollback is likewise a complete previous Home generation, which
recreates its matching configuration before starting its matching Chroma.

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

## Codex 0.152.1 and ChatGPT Desktop 26.831.21537 persistent-owner crossing

This generation advances the single declared Codex CLI to `0.152.1` and the
official signed ChatGPT Desktop package to `26.831.21537`; the independently
packaged Codex sidebar advances to `26.5825.51511`.  The Desktop app is still
only a client of the existing `codex-remote-control` owner.  Its packaged
resolver reaches the same declared Codex executable, while its private
`codex_app` App Tools MCP producer remains disabled so it cannot create a
private server or inject configuration rejected by the shared owner.

Deploy the complete Home generation before touching the running owner. Verify
`codex --version` reports `codex-cli 0.152.1`, and verify the Desktop package
version through the installed package metadata.  If the currently managed
owner must adopt the new CLI, restart only `codex-remote-control` when no
managed session has an in-flight turn; clients reconnect through the existing
control route.  The restart replaces the owner process, so no in-flight turn
or process-local session state is preserved.  Do not launch a second
app-server, use `direct-codex` as a normal client, or permit Desktop to fall
back to a bundled resolver.  This declarative update neither changes local
Codex transcript files nor migrates account-side conversation state.

## Claude Fable 5.1 and persistent Remote Control

This generation moves the declared Claude Code CLI, Claude Code VSIX, and
Claude Desktop together. Claude Code 2.1.257 introduced
`claude-fable-5-1` and made it the current Fable picker entry, while the
package is pinned at 2.1.258. The persistent `claude-remote-control` owner
remains model-neutral: selecting a model is a new-session decision, not a
global Home policy.

Deploy the resulting Home revision before changing the running owner. Verify
the installed CLI with `claude --version`, then restart only the owner with
`systemctl --user restart claude-remote-control` when no managed session has
an in-flight turn. A restart replaces the owner process, so attached Claude
Desktop, browser, and mobile clients reconnect through Anthropic's relay.
There is no process-level session preservation across that restart: defer it
until the current work is safe to interrupt. The declaration neither rewrites
local Claude transcript files nor migrates account-side conversation/model
state; whether an interrupted Remote Control session can be reopened is
Anthropic relay behavior, not a Home migration guarantee. To start a new
terminal session with Fable, use `claude --model claude-fable-5-1`; in Claude
Desktop, browser, and mobile, choose **Fable 5.1** from the upstream model
picker. Fable 5.1 uses 30-day safety-monitoring retention by default; do not
select it where that retention is unacceptable.

Do not use a stateful Claude Code update or allow Desktop to download its own
CLI. If the post-activation CLI is not the pinned version or the Remote
Control owner does not restart, leave the previous owner stopped and repair
the declarative generation before creating further sessions.

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
