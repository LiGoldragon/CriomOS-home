# The one projected Horizon every check consumes.
#
# `horizon-projection.json` is not hand-written. It is the exact output of the
# real producer:
#
#   horizon-cli --node atlas < horizon-definition.datom
#
# run against horizon-rs `8f4240ef23024c2d3b55f803d96d3c6e7aa5b433` — the
# revision lojix pins and materializes into the `horizon` flake input at deploy
# time. Lojix's materialized flake is literally
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
builtins.fromJSON (builtins.readFile ./horizon-projection.json)
