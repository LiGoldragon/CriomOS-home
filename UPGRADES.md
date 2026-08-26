# Upgrades

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
