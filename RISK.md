# Risk note — cr-ygc4tl CriomOS-home pin

## Patch risk

This patch updates the `gascity` flake input from `gascity-nix 972fd56`
(v1.0.0 plus Codex model patch deploy) to `gascity-nix 61894aa`
(gascity source pinned to session sleep managed default). The main
runtime risk is that the next home or system activation receives the
newer `gc` binary and therefore changes non-always agent idle-sleep
defaults.

## Coverage

`nix flake metadata --json github:LiGoldragon/CriomOS-home/908b205`
shows the `gascity` lock at
`61894aa60908dc548e97de1ccf50f6146026f69e`.
`nix build github:LiGoldragon/gascity-nix/61894aa#default --refresh
--no-link` succeeds.

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
