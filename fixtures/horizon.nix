# The one projected Horizon every check consumes.
#
# `horizon-projection.json` is not hand-written. It is the exact output of the
# real producer:
#
#   horizon-cli --node atlas < horizon-definition.datom
#
# run against horizon-rs `8f4240ef23024c2d3b55f803d96d3c6e7aa5b433`, and
# re-run byte-identically against `40d04d2504fee619e9b2b2564b8a769a3a9d6049`
# (horizon-lib 0.10.1) — the revision the OS deployment path currently pins
# and materializes into the `horizon` flake input. What it materializes is
# literally
# `{ outputs = _: { horizon = builtins.fromJSON (builtins.readFile ./horizon.json); }; }`
# over the same serialization, so a check reading this file sees precisely the
# attribute set a deploy-time evaluation sees.
#
# Hand-written fixtures are what let `node.machine.arch` survive here after the
# producer had been emitting `node.machine.architecture` for months: a fixture
# authored to match the consumer can never disagree with it. Regenerate this
# file from the producer when the pinned horizon-rs revision moves; never edit
# it to make a check pass.
#
# `horizon-definition.datom` is the composed definition the projection came
# from, kept beside it so the regeneration is reproducible.
#
# The deployment tool is deliberately not named here:
# `checks/system-projection-boundary` forbids that name in every Home `.nix`
# source, because Home must not carry an OS deployment edge.
builtins.fromJSON (builtins.readFile ./horizon-projection.json)
