# Upgrades

## Claude Remote Control removal

The `claude-remote-control` user service, its `criomos.claudeRemoteControl`
options, and its contract check are removed. Every minimum Home profile
previously started a persistent Claude session owner with `Restart=always`
and `RestartSec=2s`; nothing declares one now, and there is no disabled
option or compatibility stub to migrate. Any per-user projection that set
`criomos.claudeRemoteControl.workingDirectory` or `.spawn` must drop that
setting — the option no longer exists and evaluation fails on it.

Activating this generation removes the unit from the Home-managed set. A unit
already running from the previous generation survives activation, so stop and
disable it once on each account that had it:
`systemctl --user disable --now claude-remote-control.service`. Claude Code
remains installed and unchanged as a terminal harness. The independent
`codex-remote-control` owner is untouched.

## Flow identity helper

After activating a generation pinned to `harness`'s `flow-id`, a parent flow claims its lane with `flow-id codex --flows-root /absolute/flows-root` or `flow-id claude --flows-root /absolute/flows-root --parent-session UUID` before writing its first artifact.

Codex starts from normalized UUID characters `[23:29]`; Claude accepts a canonical lowercase RFC 4122 UUIDv4 or UUIDv5 parent session with variant nibble `8`, `9`, `a`, or `b` and starts from its first six literal hexadecimal characters. New private Claude markers retain the UUID version. The alias is `FLOW_ID`; its lane is `FLOW_DIRECTORY`. Existing unmarked lanes remain collisions and are never overwritten. Child threads receive those parent values and do not claim lanes.

Claude callers with malformed, unsupported-version, noncanonical, or invalid-variant parent IDs must provide the authoritative canonical UUIDv4 or UUIDv5 parent session. The Home wrapper does not infer or fall back to a Claude environment variable.

The current `harness` pin publishes each versioned marker only after complete
private metadata is ready under a stable private claim lock. A concurrent
parent claim therefore cannot read a partial marker; malformed markers still
fail closed. New Claude markers encode `uuid-version=uuid-v4` or
`uuid-version=uuid-v5`; deployed untyped v4 markers stay compatible.

## Terminal scopes survive a kernel OOM kill

This generation installs `~/.config/systemd/user/app-ghostty-.scope.d/oom-policy.conf`
(`OOMPolicy=continue`) and starts the rescue terminal scope with the same
property. Ghostty's per-surface `app-ghostty-surface-transient-<pid>.scope`
units no longer stop, together with every process in them, when the kernel
OOM killer takes one of their processes; the user manager's
`DefaultOOMPolicy=stop` stays in force for everything else.

Activation only links the drop-in and reloads the user manager; no service
restarts. Surfaces opened after that reload carry `OOMPolicy=continue`
(`systemctl --user show app-ghostty-surface-transient-<pid>.scope -p OOMPolicy`);
a surface that was already running keeps the `stop` it was started with until
it is closed and reopened. Live sessions are not interrupted.

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

## ChatGPT Desktop stock boundary with Node-report workaround

This generation retains the stock ChatGPT Desktop boundary: its bundled
`resources/codex` Desktop Core remains vendor byte-for-byte, and the wrapper
neither forces the local-daemon route nor clears vendor CLI/App Tools selection
variables. The Wayland launch argument remains unchanged.

The vendor `app.asar` has one narrowly scoped, byte-length-preserving change:
the single Linux `isLinux() && process.report` guard in `@parcel/watcher`'s
vendored `detect-libc` helper becomes `false /* nix:skip report */`. Deployed
stock 26.901.20858 repeatedly crashed with `SIGILL` in its Git worker at
Node's diagnostic-report CFI trap. The guard is the sole ASAR process-report
call and matches that native stack, so its exact JavaScript invocation is an
inference rather than a dynamic trace. The package contract derives its
expected ASAR independently from the signed vendor archive and rejects every
difference except this one guard.

Deploy the complete Home generation through the normal declarative path. Do
not patch the installed application, replace `resources/codex`, or add any
Desktop-to-persistent-Codex bridge. A new Desktop window uses the vendor
private Core; it is not a client of `codex-remote-control` and does not share
that owner's process-local state.

The independent persistent owner remains for terminal Codex routing and phone
Remote Control. Agent Intercom, the VSCodium sidebar, and full-access defaults
are unchanged. Do not restart `codex-remote-control` merely for this Desktop
rollback. The package check compares the delivered ASAR and bundled Core with
an independently extracted fixed-output OpenAI archive and exercises the
generated wrapper with inherited vendor variables plus Wayland selection.

## Claude Fable 5.1

This generation moves the declared Claude Code CLI, Claude Code VSIX, and
Claude Desktop together. Claude Code 2.1.257 introduced
`claude-fable-5-1` and made it the current Fable picker entry, while the
package is pinned at 2.1.258.

Deploy the resulting Home revision, then verify the installed CLI with
`claude --version`. To start a new terminal session with Fable, use
`claude --model claude-fable-5-1`; in Claude Desktop, browser, and mobile,
choose **Fable 5.1** from the upstream model picker. Fable 5.1 uses 30-day
safety-monitoring retention by default; do not select it where that retention
is unacceptable.

Do not use a stateful Claude Code update or allow Desktop to download its own
CLI. If the post-activation CLI is not the pinned version, repair the
declarative generation before creating further sessions.

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
