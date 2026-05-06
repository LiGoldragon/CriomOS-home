# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix d6009c3`
(gascity source pinned to session wake metadata no-op suppression) to
`gascity-nix db66862` (gascity source pinned to
`6462edf36cefa88bde03f19439173a3bc821a708`).

The new `gc` includes the upstream issue-prefix SQL repair and the
stable-session no-op wake failure cleanup fix. The main runtime risk is
that the next home or system activation receives this newer `gc` binary
and therefore changes stable-session metadata write behavior in running
cities.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `db668627ca3293c45778390ecf1b193c74607246`
and `sha256-Am0C72J0bfG85YJDiWst3TaiuTpFsVPgdzlsIWJW5nc=`.

`nix build .#default --refresh` in the `gascity-nix db66862` worktree
succeeds, and `gc version --long` for that package reports
`6462edf36cefa88bde03f19439173a3bc821a708`.

`test-city` reproduced the dolt write-amp pattern against stock
`gascity 1.0.0`. It then validated this exact package through the
`run-idle-gascity-nix-source` lane: after startup, Dolt commits stayed
flat at 14, events stayed flat at 12, and Dolt CPU fell from the initial
startup burst to idle-level usage instead of continuing the write loop.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
