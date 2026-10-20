{
  pkgs,
  inputs,
  herdr ? pkgs.callPackage ../herdr { inherit inputs; },
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;
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
  # The launcher drives the start adapter of the pinned Primary source.
  text = ''
    export FLOW_WORKSPACE="''${FLOW_WORKSPACE:-$HOME/primary}"
    export FLOW_START_LIBRARY=${inputs.primary}/tools
    exec node ${inputs.flow}/launcher/flow-start.mjs "$@"
  '';
}
