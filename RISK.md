# Risk note — Gas City dolt-amp fix pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 3aa2e01`
(gascity source pinned to the drain write wake fix) to
`gascity-nix 5f6d5d4` (gascity source pinned to
`881f57bd5cc8d927ca1dcc1e5e5c1b036246ff8a`).

The new `gc` keeps the previous wake and managed bd fixes and adds
managed builtin-pack pruning. The main runtime risk is that the next
home or system activation receives a `gc` binary that treats
`.gc/system/packs` as an exact managed projection: stale files left by
older Gas City binaries are removed on start or reload. That is intended
for bundled pack files, but any user-edited file under `.gc/system/packs`
would be removed instead of preserved.

## Coverage

`nix flake update gascity` updated only the `gascity` node in
`flake.lock`. The new lock reports `5f6d5d427d9111143e06ed5fe1b7a223e0b256fb`
and `sha256-VqeR97mY5ZrL/FPNymdJnPIoOz2XQATXdyct8XhfS8A=`.

`nix build .#gascity` in the `gascity-nix 5f6d5d4` worktree
succeeds, and `gc version --long` for that package reports
`881f57bd5cc8d927ca1dcc1e5e5c1b036246ff8a`.

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

The live Criopolis repair loop exposed a stale `order-tracking-sweep`
system-pack projection whose command no longer exists in current Gas
City. Removing that stale projection stopped fresh order failures, and
`gc doctor --verbose` reported 39 passed. Gas City commit `881f57bd`
adds targeted coverage for pruning stale managed builtin files; a
broader `go test ./cmd/gc` run timed out in an existing bd recovery
status path outside the builtin-pack materialization tests.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. This patch is intended for the authorized `lojix-cli`
activation path so the `gc` on `PATH` comes from the fixed package.

## Reviewer focus

Review `flake.lock` first. The intended lock diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
