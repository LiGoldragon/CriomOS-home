{ config, lib, pkgs, ... }:
let
  cfg = config.criomosHome.codexPlain;
  package = pkgs.callPackage ../../../../owned-agents/codex-plain {};
  hash = builtins.unsafeDiscardStringContext (builtins.substring 0 12 (builtins.baseNameOf package.drvPath));
  home = "${config.home.homeDirectory}/.codex-plain-${hash}";
  socket = "${home}/app-server-control/app-server-control.sock";
  unit = "codex-app-server-plain-${hash}";
  client = pkgs.writeShellApplication {
    name = "codex-plain-flow-client";
    text = ''
      export CODEX_HOME=${lib.escapeShellArg home}
      exec ${package}/bin/codex "$@"
    '';
  };
in {
  options.criomosHome.codexPlain = {
    enable = lib.mkEnableOption "the separate plain stable Codex endpoint after isolated acceptance";
    autoStart = lib.mkOption { type = lib.types.bool; default = false; description = "Start only this new endpoint on user login after explicit adoption."; };
    authSource = lib.mkOption { type = lib.types.nullOr lib.types.str; default = null; description = "Authorized private runtime auth.json source for one-time import; no secret is held by Nix."; };
    package = lib.mkOption { type = lib.types.package; readOnly = true; default = package; };
    clientPackage = lib.mkOption { type = lib.types.package; readOnly = true; default = client; };
    homeDirectory = lib.mkOption { type = lib.types.str; readOnly = true; default = home; };
    socket = lib.mkOption { type = lib.types.str; readOnly = true; default = socket; };
    unit = lib.mkOption { type = lib.types.str; readOnly = true; default = unit; };
  };
  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.clientPackage ];
    systemd.user.services.${unit} = {
      Unit.Description = "Plain stable Codex app-server ${hash}";
      Unit."X-SwitchMethod" = "keep-old";
      Service = {
        Environment = [ "CODEX_HOME=${home}" ];
        WorkingDirectory = config.home.homeDirectory;
        ExecStartPre = pkgs.writeShellScript "codex-plain-private-home" (''
          set -eu
          install -d -m700 ${lib.escapeShellArg home}
        '' + lib.optionalString (cfg.authSource != null) ''
          if [ ! -e ${lib.escapeShellArg "${home}/auth.json"} ]; then
            install -m600 ${lib.escapeShellArg cfg.authSource} ${lib.escapeShellArg "${home}/auth.json"}
          fi
        '');
        ExecStart = "${package}/bin/codex app-server --remote-control --listen unix://${socket}";
        UMask = "0077";
        KillMode = "process";
        Restart = "no";
        LimitNOFILE = 524288;
      };
      Install.WantedBy = lib.optional cfg.autoStart "default.target";
    };
  };
}
