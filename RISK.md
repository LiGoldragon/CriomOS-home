# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix d4daa0e`
(gascity source pinned to the session reconciliation fix) to
`gascity-nix 93e2059` (gascity source pinned to
`0bc6e58522eacdf3da7f2567724d97c9ab7b4ad7`).

The new `gc` keeps the previous wake, managed bd, stale builtin-pack,
daemon-only compactor disablement, and cached metadata no-op fixes. It adds
the direct session reconciler guard for already-clear wake failure metadata
and pending-create in-flight accounting, plus a follow-up fix for stopped
pending-create sessions.

The main runtime risk is that a legitimate metadata refresh that
intentionally writes an identical value no longer advances the bead's
`updated_at`; consumers should treat unchanged metadata as no state
transition. Pending-create accounting still delays true `state=creating`
retries until the startup timeout expires instead of immediately minting
another pool session, but `state=stopped` pending-create claims retry on the
next tick.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `93e2059cfc3fd96c7cd157c189b238fbd01913a7`
and `sha256-Q6k0NKxv59hsR0cs0eqDRO6yfnCllujy0WGvdNVTdQk=`.

`nix build .#gascity` in the `gascity-nix 93e2059` worktree
succeeds, and `gc version --long` for that package reports
`0bc6e58522eacdf3da7f2567724d97c9ab7b4ad7`.

`test-city` reproduced the dolt write-amp pattern against stock
`gascity 1.0.0`. It then validated this exact package through the
`run-idle-gascity-nix-source` lane: after startup, Dolt commits stayed
flat at 14, events stayed flat at 12, and Dolt CPU fell from the initial
startup burst to idle-level usage instead of continuing the write loop.

Additional `test-city` PATH testing found the dormant wake regression in
the previous pin: after `gc session suspend auditor` stopped the runtime,
`gc session wake auditor` returned success but did not restart the
on-demand named session, and the controller later reaped it as stale. The
new Gas City commits add targeted tests for explicit wake metadata, the
active-with-user-hold race observed during suspend drain, and the stale
drain-completion write that could clear a newer pending create claim.
The latest Gas City commit adds a second guard for stale drain writes
that read before the wake claim commits and land afterward.

The live Criopolis repair loop then exposed two additional production
misbehaviors: `mol-dog-compactor` was being poured to dog agents even
though its formula is daemon-only, and the mayor/control-dispatcher
session beads were emitting unchanged `bead.updated` events every few
seconds. Gas City commit `4e994724` added targeted coverage for both:
disabled builtin order scanning and CachingStore identical-metadata
no-op writes. The live loop still showed mayor/control-dispatcher writes,
so `5b14365c` adds a direct `clearWakeFailures` no-op guard and regression
tests for that reconciler path.

Restarting Criopolis with `5b14365c` then exposed a five-minute mayor wake
delay: the bead was `state=stopped` with `pending_create_claim=true`, so the
new pending-create throttle treated it as still in-flight until the startup
timeout. Gas City commit `0bc6e585` narrows the throttle to actual
`state=creating` starts.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is consumed by CriomOS. It
does not own or authorize deployment; the OS selects and activates Home through
its own deployment path.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
