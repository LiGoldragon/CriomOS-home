# Risk note — cr-ygc4tl CriomOS-home pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 61894aa`
(gascity source pinned to session sleep managed default) to
`gascity-nix d6009c3` (gascity source pinned to session wake metadata
no-op suppression). The main runtime risk is that the next home or
system activation receives the newer `gc` binary and therefore changes
stable-session metadata write behavior in running cities.

## Coverage

`nix flake lock --update-input gascity` updated only the `gascity`
node in `flake.lock`. `nix build .#default --refresh` in the
`gascity-nix d6009c3` worktree succeeds, and `./result/bin/gc version
--long` reports `a720d067c0fcc9b77054222da5be6fac98091217`.
`nix flake metadata --json . | jq -r
'.locks.nodes.gascity.locked.rev, .locks.nodes.gascity.locked.narHash'`
reports `d6009c31f03eb1ed6705fc6c5cedfcc82329dd45` and
`sha256-FJknRVEegO+Ckvy3ebp6t2N1e4F+8dOM3pdHRRPFqyY=`.

Full `nix flake check github:LiGoldragon/CriomOS-home/908b205
--refresh` fails because blueprint exposes
`checks.x86_64-linux.pkgs-formatter-__ignoreNulls` as a non-derivation.
The same failure occurs on parent commit `CriomOS-home 7bb3082`
(Document Pi extension packaging), so this is pre-existing and not
introduced by the lock update.

## Cross-repo effects

`CriomOS-home` feeds the operator home profile and is also consumed by
CriomOS. Mayor or Li must still run the authorized deployment path; this
patch does not activate Home Manager, run `lojix-cli`, or restart
supervised sessions.

## Reviewer focus

Review `flake.lock` first. The intended diff is only the `gascity`
node's `rev`, `narHash`, and `lastModified`.
