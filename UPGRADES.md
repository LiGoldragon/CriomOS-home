# Upgrades

## Unified Codex app-server clients

This generation makes the per-user `codex-remote-control` service the only
normal Codex thread writer. Terminal `codex`, ChatGPT Desktop, and the phone
are clients of its Unix WebSocket socket. Closing a terminal or Desktop window
detaches that client; it must not be used to stop the service.

Before activating, stop any manually started Codex app-server process. After
activation, confirm `systemctl --user is-active codex-remote-control` and run
`codex app-server daemon version`. If either fails, Desktop fails closed rather
than falling back to a bundled or host Codex writer. Repair the managed unit or
its pinned package, then restart the unit; do not start a second app-server.

`direct-codex` is the explicit raw recovery escape. It bypasses the normal
client-routing guard and can create a separate writer, so use it only to repair
or diagnose a failed managed service. It is not a normal terminal entry point.

The packaged checks exercise the gate, its actual Electron `resources/codex`
path, the native-mode launch environment, and daemon WebSocket reconnects. They
do not yet drive the Electron GUI through a graphical Desktop connection; that
final GUI-native smoke remains a deployment-time observation boundary.

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
