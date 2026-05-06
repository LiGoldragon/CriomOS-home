# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 5f6d5d4`
(gascity source pinned to the builtin-pack pruning fix) to
`gascity-nix 8c51b8f` (gascity source pinned to
`4e9947249320618b8a2a1d94d13e8a2715360d5a`).

The new `gc` keeps the previous wake and managed bd fixes and adds
two Criopolis repair fixes: the daemon-only Dolt compactor order is
disabled, and cached no-op metadata writes are suppressed before they
reach `bd update`. The main runtime risk is that a legitimate metadata
refresh that intentionally writes an identical value no longer advances
the bead's `updated_at`; consumers should treat unchanged metadata as no
state transition.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `8c51b8fc9a88d69272857a0098023f1a1b49294d`
and `sha256-Z2pM7q6tGue4spDRzGEhRON8jOyq5CQAeTP/Xst4aHg=`.

`nix build .#gascity` in the `gascity-nix 8c51b8f` worktree
succeeds, and `gc version --long` for that package reports
`4e9947249320618b8a2a1d94d13e8a2715360d5a`.

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
seconds. Gas City commit `4e994724` adds targeted coverage for both:
disabled builtin order scanning and CachingStore identical-metadata
no-op writes.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
