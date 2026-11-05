{
  lib,
  pkgs,
  inputs,
  user,
  ...
}:
let
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  runtimeInputs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/runtime-inputs.nix" { };
  wisprFlow = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/wispr-flow.nix" {
    inherit runtimeInputs;
  };
  wisprFlowFhs = pkgs.callPackage "${inputs.wispr-flow-linux}/nix/fhs.nix" {
    wispr-flow = wisprFlow;
  };
in
lib.mkIf (sizeAtLeast "Medium") {
  # A paid proprietary desktop client belongs to the medium Home tier, not to
  # one account. Higher profile tiers inherit medium capability.
  home.packages = [ wisprFlowFhs ];

  systemd.user.services.wispr-flow = {
    Unit = {
      Description = "Wispr Flow speech-to-text client";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${wisprFlowFhs}/bin/wispr-flow";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };
}
