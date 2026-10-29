{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = inputs.primary.packages.${system}.curriculum;
  cohort = inputs.primary.inputs;
  environment = _homeDirectory: [
    "CURRICULUM_CONTEXT_LAYOUT=2"
    "CURRICULUM_PSYCHES_REPOSITORY_DIR=${cohort.psyche-context}"
    "CURRICULUM_PSYCHES_REVISION=${cohort.psyche-context.rev}"
    "CURRICULUM_MIND_CONTEXT_DIR=${cohort.mind-context}"
    "CURRICULUM_MIND_REVISION=${cohort.mind-context.rev}"
    "CURRICULUM_FIELD_CONTEXT_DIR=${cohort.field-context}"
    "CURRICULUM_FIELD_REVISION=${cohort.field-context.rev}"
    "CURRICULUM_ROLES_FILE=${cohort.curriculum}/roles.datom"
  ];
  cli = pkgs.writeShellScriptBin "curriculum" ''
    exec ${runtime}/bin/curriculum "$@"
  '';
in
assert cohort.curriculum.rev == "73330192326f443605589614707d8ce91d15e449";
pkgs.runCommand "curriculum-resolver-deployment" {
  passthru = {
    inherit runtime environment;
    inherit (cohort) psyche-context mind-context field-context;
  };
} ''
  mkdir -p "$out/bin"
  ln -s ${cli}/bin/curriculum "$out/bin/curriculum"
''
