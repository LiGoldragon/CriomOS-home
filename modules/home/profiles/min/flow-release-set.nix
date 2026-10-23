{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.criomosHome.flow.releaseSet;
  system = pkgs.stdenv.hostPlatform.system;
  releaseType = lib.types.submodule {
    options = {
      generation = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9-]+";
      };
      package = lib.mkOption {
        type = lib.types.package;
      };
    };
  };
  release = channel: value:
    if value == null then null else {
      inherit (value) generation;
      runtime = value.package;
      runtimeDirectory = "flow-release-${value.generation}";
      stateDirectory = "flow-release-${value.generation}";
      herdrSession = "flow-${value.generation}";
      inherit channel;
    };
  releases = {
    stable = release "stable" cfg.stable;
    last = release "last" cfg.last;
    next = release "next" cfg.next;
  };
  available = lib.filterAttrs (_: value: value != null) releases;
  aliasSet = pkgs.callPackage ../../../../packages/flow-release-set {
    inherit inputs releases;
    selected = cfg.selected;
  };
  service = channel: value:
    let
      deployment = pkgs.callPackage ../../../../packages/flow-deployment {
        inherit inputs;
        inherit (value) runtime stateDirectory runtimeDirectory;
      };
    in {
      Unit = {
        Description = "Flow Nexus ${channel} release ${value.generation}";
        Requires = [ "curriculum-nexus.service" ];
        After = [ "curriculum-nexus.service" ];
      };
      Service = {
        Type = "simple";
        Environment = [
          "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
          "FLOW_RELEASE_CHANNEL=${channel}"
          "HERDR_SESSION=${value.herdrSession}"
        ];
        ExecStartPre = "${deployment.initialize}/bin/initialize-declared-flow";
        ExecStart = "${value.runtime}/bin/flow-nexus \"{ %t/${value.runtimeDirectory}/flow.sock %t/${value.runtimeDirectory}/flow-meta.sock %h/.local/state/${value.stateDirectory}/flow.sema None }\"";
        ExecStartPost = "${deployment.ready}/bin/wait-declared-flow-ready";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
in
{
  options.criomosHome.flow.releaseSet = {
    enable = lib.mkEnableOption "isolated Flow stable/last/next release set";
    selected = lib.mkOption {
      type = lib.types.enum [ "stable" "last" "next" ];
      default = "stable";
      description = "The whole Flow generation selected by the atomic alias package.";
    };
    stable = lib.mkOption {
      type = releaseType;
      default = {
        generation = "938ec35";
        package = inputs.flow.packages.${system}.default;
      };
    };
    last = lib.mkOption {
      type = lib.types.nullOr releaseType;
      default = null;
    };
    next = lib.mkOption {
      type = lib.types.nullOr releaseType;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.hasAttr cfg.selected available;
        message = "Flow release ${cfg.selected} is unavailable";
      }
    ];
    home.packages = [ aliasSet ];
    systemd.user.services = lib.mapAttrs' (channel: value:
      lib.nameValuePair "flow-nexus-release-${channel}" (service channel value)
    ) available;
  };
}
