{
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  runtimeInputs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/runtime-inputs.nix" { };
  wisprFlow = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/wispr-flow.nix" {
    inherit runtimeInputs;
    installerExe = inputs.wispr-flow-installer;
  };
  wisprFlowFhs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/fhs.nix" {
    wispr-flow = wisprFlow;
  };
in
lib.mkIf (user.name == "li") {
  # A paid proprietary desktop client is a personal selection, not a shared
  # service.  It has no Home service, autostart, or keybinding declaration.
  home.packages = [ wisprFlowFhs ];
}
