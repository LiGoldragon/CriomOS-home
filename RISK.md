# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 5e81ad2`
(gascity source pinned to the stale drain-completion wake fix) to
`gascity-nix 3aa2e01` (gascity source pinned to
`60732751665b4c70685f06a425febbe96eeb6286`).

The new `gc` includes the upstream issue-prefix SQL repair and the
stable-session no-op wake failure cleanup fix, plus an explicit wake fix
for dormant sessions. It also preserves controller wake claims when
drain-ack or drain-completion metadata writes land after an explicit
wake. The main runtime risk is that the next home or system activation
receives this newer `gc` binary and therefore changes session wake
behavior in running cities: `gc session wake` now records a one-shot
start request for asleep, suspended, drained, and stopped sessions
instead of only clearing wake blockers.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `3aa2e01c480ccd042c321802095bc7d599763579`
and `sha256-GigUB7Ba6AmbJMq/FC/iOfrezWEW4b3b+fCAla74GFQ=`.

`nix build .#gascity` in the `gascity-nix 3aa2e01` worktree
succeeds, and `gc version --long` for that package reports
`60732751665b4c70685f06a425febbe96eeb6286`.

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

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
