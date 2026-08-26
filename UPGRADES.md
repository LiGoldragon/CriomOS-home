# Upgrades

## Orchestrate Nexus

Home now starts `orchestrate-nexus` for every user. The retired
`orchestrate-daemon` service, its PersonaDevelopment gate, its seven-argument
startup contract, and the `PERSONA_ORCHESTRATE_*` client variables are removed.

The Nexus starts with its built-in default configuration. Home provides no
bootstrap writer, frame, or configuration file. Its client wrappers now set
`ORCHESTRATE_SOCKET` and `ORCHESTRATE_META_SOCKET` to the standard user runtime
paths.

The Nexus uses `$XDG_STATE_HOME/orchestrate-nexus/orchestrate-nexus.sema`. The
legacy `$XDG_STATE_HOME/orchestrate/orchestrate.sema` store is deliberately
left in place and is neither opened nor migrated. After activating a Home
generation, use the new `orchestrate` wrapper to register future path locks.
