{
  pkgs,
  inputs,
  herdr ? pkgs.callPackage ../herdr { inherit inputs; },
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
  # The launcher imports its library from the pinned Primary source, so the
  # script and the start adapter it drives are one immutable pair.
  script = pkgs.replaceVars ./flow-start.mjs { primary = "${inputs.primary}"; };
in
pkgs.writeShellApplication {
  name = "flow-start";
  runtimeInputs = [
    pkgs.nodejs
    pkgs.babashka
    pkgs.git
    inputs.flow.packages.${system}.default
    inputs.messenger-clj.packages.${system}.default
    herdr
  ];
  text = ''
    export FLOW_WORKSPACE="''${FLOW_WORKSPACE:-$HOME/primary}"
    exec node ${script} "$@"
  '';
}
