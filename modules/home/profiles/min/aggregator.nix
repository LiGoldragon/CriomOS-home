{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf mkOption;
  inherit (lib.types) bool;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  aggregatorPackage = inputs.aggregator.packages.${system}.default;

  stateDirectory = "${config.xdg.stateHome}/aggregator";
  configurationPath = "${stateDirectory}/configuration.nota";
  storePath = "${stateDirectory}/aggregator.sema";
  runtimeDirectoryName = "aggregator";

  primaryClaudeProjectRoot = "${config.home.homeDirectory}/.claude/projects/-home-li-primary";

  writeDefaultConfiguration = pkgs.writeShellScript "aggregator-default-configuration" ''
    set -eu

    state_directory=${lib.escapeShellArg stateDirectory}
    configuration_path=${lib.escapeShellArg configurationPath}
    store_path=${lib.escapeShellArg storePath}
    primary_claude_project_root=${lib.escapeShellArg primaryClaudeProjectRoot}
    uid="$(${pkgs.coreutils}/bin/id -u)"
    runtime_directory="''${XDG_RUNTIME_DIR:-/run/user/$uid}/${runtimeDirectoryName}"
    claude_subagent_output_root="/tmp/claude-$uid"

    ${pkgs.coreutils}/bin/mkdir -p \
      "$state_directory" \
      "$runtime_directory" \
      "$primary_claude_project_root" \
      "$claude_subagent_output_root"
    ${pkgs.coreutils}/bin/chmod 0700 \
      "$state_directory" \
      "$runtime_directory" \
      "$primary_claude_project_root" \
      "$claude_subagent_output_root"

    ${aggregatorPackage}/bin/aggregator-write-configuration \
      --configuration "$configuration_path" <<EOF
    ($runtime_directory/aggregator.sock 384 $runtime_directory/aggregator-meta.sock 384 $store_path [] [(Claude ($primary_claude_project_root)) (ClaudeSubagentOutput ($claude_subagent_output_root))] MetadataOnly (32 4096) ((DaemonLocalStorePath OpaqueStaleCapable FragileReferenceAscending) (64 4096 65536 1024) []))
    EOF
    ${pkgs.coreutils}/bin/chmod 0600 "$configuration_path"
  '';

  initializeState = pkgs.writeShellScript "aggregator-startup-state" ''
    set -eu

    uid="$(${pkgs.coreutils}/bin/id -u)"
    runtime_directory="''${XDG_RUNTIME_DIR:-/run/user/$uid}/${runtimeDirectoryName}"

    ${writeDefaultConfiguration}
    ${pkgs.coreutils}/bin/rm -f \
      "$runtime_directory/aggregator.sock" \
      "$runtime_directory/aggregator-meta.sock"
  '';

  aggregatorProfilePackage =
    pkgs.runCommand "${aggregatorPackage.name}-profile" { nativeBuildInputs = [ pkgs.makeWrapper ]; }
      ''
        mkdir -p "$out/bin"
        for binary in ${aggregatorPackage}/bin/*; do
          ln -s "$binary" "$out/bin/$(basename "$binary")"
        done
        rm "$out/bin/aggregator" \
          "$out/bin/meta-aggregator" \
          "$out/bin/aggregator-daemon" \
          "$out/bin/aggregator-write-configuration"
        makeWrapper ${aggregatorPackage}/bin/aggregator "$out/bin/aggregator" \
          --set AGGREGATOR_CONFIGURATION ${lib.escapeShellArg configurationPath}
        makeWrapper ${aggregatorPackage}/bin/meta-aggregator "$out/bin/meta-aggregator" \
          --set AGGREGATOR_CONFIGURATION ${lib.escapeShellArg configurationPath}
        makeWrapper ${aggregatorPackage}/bin/aggregator-daemon "$out/bin/aggregator-daemon" \
          --set AGGREGATOR_CONFIGURATION ${lib.escapeShellArg configurationPath}
        makeWrapper ${aggregatorPackage}/bin/aggregator-write-configuration "$out/bin/aggregator-write-configuration" \
          --set AGGREGATOR_CONFIGURATION ${lib.escapeShellArg configurationPath}
      '';
in
{
  options.criomosHome.aggregator = {
    enable = mkOption {
      type = bool;
      default = inputs ? aggregator;
      description = "Install aggregator and supervise its local recovery daemon in the user session when a fixed and audited aggregator source is pinned as a flake input.";
    };
  };

  config = mkIf (size.min && config.criomosHome.aggregator.enable) {
    home.packages = [ aggregatorProfilePackage ];

    home.activation.aggregatorState = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD ${writeDefaultConfiguration}
    '';

    systemd.user.services.aggregator-daemon = {
      Unit = {
        Description = "Aggregator local agent recovery daemon";
        StartLimitIntervalSec = 60;
        StartLimitBurst = 5;
      };

      Service = {
        RuntimeDirectory = runtimeDirectoryName;
        RuntimeDirectoryMode = "0700";
        ExecStartPre = "${initializeState}";
        ExecStart = "${aggregatorProfilePackage}/bin/aggregator-daemon";
        Restart = "on-failure";
        RestartSec = "2s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
