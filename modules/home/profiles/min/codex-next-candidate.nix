{ config, inputs, lib, pkgs, user, ... }:
let
  enabled = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size "Min";
  birdTarget = user.name == "bird" && user.hasPublicKey && user.size == "Max" && config.home.username == "bird" && config.home.homeDirectory == "/home/bird";
  package = pkgs.callPackage ../../../../owned-agents/codex-next-candidate { };
  # Unit names and state directories need the derivation identity, but a
  # systemd filename cannot retain the derivation's store-path context.
  hash = builtins.unsafeDiscardStringContext (builtins.substring 0 12 (builtins.baseNameOf package.drvPath));
  candidateHome = "${config.home.homeDirectory}/.codex-next-${hash}";
  socket = "${candidateHome}/app-server-control/app-server-control.sock";
  unit = "codex-remote-control-next-${hash}";
  # The future `codex-next` command is the only launcher selecting the new,
  # hash-identified candidate endpoint.  Plain `codex` remains on stable.
  client = pkgs.writeShellApplication { name = "codex-next"; text = ''export CODEX_HOME=${lib.escapeShellArg candidateHome}; exec ${package}/bin/codex --remote ${lib.escapeShellArg "unix://${socket}"} "$@"''; };
  flowClient = pkgs.writeShellApplication { name = "codex-next-flow-client"; text = ''export CODEX_HOME=${lib.escapeShellArg candidateHome}; exec ${package}/bin/codex "$@"''; };
in {
  options.criomosHome.codexNextCandidate = {
    package = lib.mkOption { type = lib.types.package; readOnly = true; default = package; };
    hash = lib.mkOption { type = lib.types.str; readOnly = true; default = hash; };
    clientPackage = lib.mkOption { type = lib.types.package; readOnly = true; default = flowClient; };
    remoteClientPackage = lib.mkOption { type = lib.types.package; readOnly = true; default = client; };
    unit = lib.mkOption { type = lib.types.str; readOnly = true; default = unit; };
  };
  config = lib.mkIf (enabled && !birdTarget) {
    home.packages = [ client ];
    # The app-used home gets the same permission defaults as ~/.codex and
    # ~/.codex-next; without them its threads ran on-request and asked the
    # living (24 prompts on 2026-09-30, flow 28d847 inventory).
    home.activation.mergeCodexNextCandidatePermissionDefaults = inputs.hexis.lib.mkManagedConfig {
      inherit lib pkgs;
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      file = "${candidateHome}/config.toml";
      declared = import ./codex-permission-defaults.nix;
    };
    systemd.user.services.${unit} = { Unit.Description = "Codex Remote Control next candidate ${hash}"; Service = { WorkingDirectory = "${config.home.homeDirectory}/primary"; Environment = [ "CODEX_HOME=${candidateHome}" ]; ExecStartPre = "${pkgs.bash}/bin/bash -c 'set -eu; mkdir -p ${candidateHome}; for f in auth.json; do if [ ! -e ${candidateHome}/$f ] && [ -f ${config.home.homeDirectory}/.codex-next/$f ]; then install -m600 ${config.home.homeDirectory}/.codex-next/$f ${candidateHome}/$f; fi; done'"; ExecStart = "${package}/bin/codex app-server --remote-control --listen unix://${socket}"; UMask = "0077"; LimitNOFILE = 524288; Restart = "on-failure"; RestartSec = "2s"; }; Install.WantedBy = [ "default.target" ]; };
  };
}
