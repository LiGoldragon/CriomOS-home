{
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  runtimeInputs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/runtime-inputs.nix" { };
  wisprFlow = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/wispr-flow.nix" { inherit runtimeInputs; };
  wisprFlowFhs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/fhs.nix" {
    wispr-flow = wisprFlow;
  };
in
lib.mkIf user.size.medium {
  # A paid proprietary desktop client belongs to the medium Home tier, not to
  # one account. Higher profile tiers inherit medium capability. It has no Home
  # service, autostart, or keybinding declaration.
  home.packages = [ wisprFlowFhs ];
}
