# Managed Codex stable role

`owned-agents/codex/default.nix` is the canonical Home Codex package. Its
current `0.158.0-alpha.9` value is a local role promotion: it is the exact
immutable package previously running as the isolated Next server. It does not
label the upstream prerelease as an upstream stable release.

Before this promotion, this path built the latest non-prerelease upstream
Codex source and `update.py` skipped prereleases. That policy did not express
the managed-channel decision to promote the witnessed Next candidate, so it
is not active for this package now. New candidates are pinned separately in
`../codex-next/default.nix`; a candidate becomes this package only through an
explicit reviewed promotion with release-asset hashes for every supported
platform.

To restore upstream-stable tracking, replace this binary package with the
source package and reconnect its updater and hash data in the same change. Do
not run the old updater against this promoted binary package or infer a
managed-channel role from upstream prerelease/stable labels.
