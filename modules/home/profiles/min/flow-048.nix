{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
# Flow Nexus 0.48, a versioned unit beside the running Flow Nexus 0.44. It
# opens its own store and serves its own sockets; nothing of 0.44 is touched.
#
# A 0.48 client names the Nexus's socket inside its Invocation datom
# (`flow '{ «socket» Query }'`, `flow-meta '{ «meta-socket» Query }'`);
# no 0.48 client has a default socket. The Nexus writes its ordinary socket
# into the hook configuration of every Claude pane it launches, so its own
# flows report back to it with nothing read from the environment.
let
  cfg = config.criomosHome.flow048;
  system = pkgs.stdenv.hostPlatform.system;
  home = config.home.homeDirectory;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  pathOnly = builtins.unsafeDiscardStringContext;
  nextCodexHome = "${home}/.codex-next-${config.criomosHome.codexNextCandidate.hash}";
  # Flow 0.48 is built only through mkFlowPackage: its executable carries the
  # configuration a new, unconfigured store opens with. Later changes go over
  # the meta socket.
  runtime = inputs.flow-048.lib.${system}.mkFlowPackage {
    defaultConfiguration = {
      sourceRoot = "${home}/primary";
      runtimeDirectory = cfg.curriculumRuntimeDirectory;
      stableCodex = {
        clientPath = pathOnly "${config.criomosHome.herdr.stableCodexClientPackage}/bin/codex-stable-flow-client";
        home = "${home}/.codex-next";
        controlSocketPath = "${home}/.codex-next/app-server-control/app-server-control.sock";
        roster = [
          "gpt-5.6-sol"
          "gpt-5.6-luna"
        ];
      };
      nextCodex = {
        clientPath = pathOnly "${config.criomosHome.codexNextCandidate.clientPackage}/bin/codex-next-flow-client";
        home = nextCodexHome;
        controlSocketPath = "${nextCodexHome}/app-server-control/app-server-control.sock";
        roster = [
          "gpt-6.1-sol"
          "gpt-6-sol"
          "gpt-6-luna"
          "gpt-6-astra"
        ];
      };
      harnessProfiles = [
        {
          harnessKind = "Claude";
          commandSigils = [
            "/"
            "!"
            "#"
          ];
          interruptKeys = [
            "esc"
            "esc"
          ];
          submitKeys = [ "enter" ];
        }
        {
          harnessKind = "Codex";
          commandSigils = [
            "/"
            "!"
          ];
          interruptKeys = [ "esc" ];
          submitKeys = [ ];
        }
      ];
      metaAspects = [ "Psyche" ];
    };
  };
  # The 0.48 clients under versioned names, so the profile's flow and
  # flow-meta stay 0.44's.
  clients = pkgs.runCommand "flow-048-clients" { } ''
    mkdir -p $out/bin
    ln -s ${runtime}/bin/flow $out/bin/flow-048
    ln -s ${runtime}/bin/flow-meta $out/bin/flow-meta-048
  '';
  socketDirectory = "%t/${cfg.runtimeDirectory}";
  start = "{ «${socketDirectory}/flow.sock» «${socketDirectory}/flow-meta.sock» «%h/.local/state/${cfg.stateDirectory}/flow.sema» None }";
in
{
  options.criomosHome.flow048 = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = config.home.username == "li";
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "flow-nexus-048";
    };
    stateDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-048";
      description = "Directory under ~/.local/state holding this Nexus's flow.sema.";
    };
    runtimeDirectory = lib.mkOption {
      type = lib.types.strMatching "flow-[a-zA-Z0-9-]+";
      default = "flow-048";
      description = "Directory under $XDG_RUNTIME_DIR holding this Nexus's flow.sock and flow-meta.sock.";
    };
    curriculumRuntimeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/run/user/1001";
      description = "Runtime directory whose curriculum/curriculum.sock a new store reaches Curriculum at.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runtime;
    };
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion =
          cfg.stateDirectory != "flow-harnessflags" && cfg.runtimeDirectory != "flow-harnessflags";
        message = "Flow Nexus 0.48 must not open the 0.44 store or sockets";
      }
    ];
    home.packages = [ clients ];
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus 0.48";
        Wants = [ "curriculum-nexus.service" ];
        After = [ "curriculum-nexus.service" ];
      };
      Service = {
        Type = "simple";
        WorkingDirectory = "%h";
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        RuntimeDirectory = cfg.runtimeDirectory;
        RuntimeDirectoryMode = "0700";
        ExecStart = "${runtime}/bin/flow-nexus \"${start}\"";
        Restart = "on-failure";
        RestartSec = "100ms";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
