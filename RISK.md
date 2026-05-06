# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 8c51b8f`
(gascity source pinned to the first idle-churn fix) to
`gascity-nix d4daa0e` (gascity source pinned to
`5b14365c244728960aa6ab13bfa34580b67a555a`).

The new `gc` keeps the previous wake, managed bd, stale builtin-pack,
daemon-only compactor disablement, and cached metadata no-op fixes. It adds
the direct session reconciler guard for already-clear wake failure metadata
and pending-create in-flight accounting.

The main runtime risk is that a legitimate metadata refresh that
intentionally writes an identical value no longer advances the bead's
`updated_at`; consumers should treat unchanged metadata as no state
transition. Pending-create accounting also delays retries until the startup
timeout expires instead of immediately minting another pool session.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `d4daa0e9ec1a628b0d55cf71bf02322e44e18d1c`
and `sha256-jDPLaeysNtlmOatN1vFU5O2YZ/Odnz8O5YMuppITmwc=`.

`nix build .#gascity` in the `gascity-nix d4daa0e` worktree
succeeds, and `gc version --long` for that package reports
`5b14365c244728960aa6ab13bfa34580b67a555a`.

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

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
