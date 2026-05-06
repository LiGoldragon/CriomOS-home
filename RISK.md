# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix db66862`
(gascity source pinned to session wake metadata no-op suppression) to
`gascity-nix 7c2809e` (gascity source pinned to
`2ebf4885dbc0183a78d0799355f141de85056857`).

The new `gc` includes the upstream issue-prefix SQL repair and the
stable-session no-op wake failure cleanup fix, plus an explicit wake fix
for dormant sessions. The main runtime risk is that the next home or
system activation receives this newer `gc` binary and therefore changes
session wake behavior in running cities: `gc session wake` now records a
one-shot start request for asleep, suspended, drained, and stopped
sessions instead of only clearing wake blockers.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `7c2809edd3d9ad7ce887b48b9fff60dbd37fd55f`
and `sha256-NaOV3DCSQ2uKgXkOBczzd1i0jY3MvjbOuliuGYG7fmo=`.

`nix build .#gascity` in the `gascity-nix 7c2809e` worktree
succeeds, and `gc version --long` for that package reports
`2ebf4885dbc0183a78d0799355f141de85056857`.

`test-city` reproduced the dolt write-amp pattern against stock
`gascity 1.0.0`. It then validated this exact package through the
`run-idle-gascity-nix-source` lane: after startup, Dolt commits stayed
flat at 14, events stayed flat at 12, and Dolt CPU fell from the initial
startup burst to idle-level usage instead of continuing the write loop.

Additional `test-city` PATH testing found the dormant wake regression in
the previous pin: after `gc session suspend auditor` stopped the runtime,
`gc session wake auditor` returned success but did not restart the
on-demand named session, and the controller later reaped it as stale. The
new Gas City commit adds targeted tests for explicit wake metadata and is
being revalidated through the lifecycle churn lane after activation.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
