{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  runtime = inputs.primary.packages.${system}.curriculum;
  cohort = inputs.primary.inputs;
  environment = homeDirectory: [
    "CURRICULUM_PSYCHES_REPOSITORY_DIR=${cohort.psyche-skills}"
    "CURRICULUM_MIND_SKILLS_DIR=${cohort.mind-skills}/skills"
    "CURRICULUM_FIELD_SKILLS_DIR=${cohort.field-skills}/skills"
    "CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom"
    "CURRICULUM_WORKSPACE=${homeDirectory}/primary"
  ];
  cli = pkgs.writeShellScriptBin "curriculum" ''
    export CURRICULUM_PSYCHES_REPOSITORY_DIR=${cohort.psyche-skills}
    export CURRICULUM_MIND_SKILLS_DIR=${cohort.mind-skills}/skills
    export CURRICULUM_FIELD_SKILLS_DIR=${cohort.field-skills}/skills
    export CURRICULUM_ROLES_FILE=${inputs.curriculum-source}/roles.datom
    export CURRICULUM_WORKSPACE="$HOME/primary"
    exec ${runtime}/bin/curriculum "$@"
  '';
  unit = pkgs.writeText "curriculum-declared-runtime.conf" (''
    [Service]
    Environment=
    Environment=XDG_RUNTIME_DIR=%t
  '' + pkgs.lib.concatMapStringsSep "\n" (value: "Environment=" + value) (environment "%h") + ''

    WorkingDirectory=%h/primary
    ExecStart=
    ExecStart=${runtime}/bin/curriculum-nexus
    ExecStartPost=
  '');
in pkgs.runCommand "curriculum-resolver-deployment" {
  passthru = { inherit runtime environment unit; inherit (cohort) psyche-skills mind-skills field-skills; };
} ''
  mkdir -p "$out/bin" "$out/share/systemd/user/curriculum-nexus.service.d"
  ln -s ${cli}/bin/curriculum "$out/bin/curriculum"
  cp ${unit} "$out/share/systemd/user/curriculum-nexus.service.d/50-declared-runtime.conf"
''
