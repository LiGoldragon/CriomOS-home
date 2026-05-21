{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (user) size;

  system = pkgs.stdenv.hostPlatform.system;
  upstreamCommandLine = inputs.persona-spirit.packages.${system}.spirit;
  daemon = inputs.persona-spirit.packages.${system}.persona-spirit-daemon;

  stateDirectory = "${config.home.homeDirectory}/.local/state/persona-spirit";
  ordinarySocketPath = "${stateDirectory}/spirit.sock";
  ownerSocketPath = "${stateDirectory}/owner.sock";
  storePath = "${stateDirectory}/persona-spirit.redb";
  configuration = ''("${ordinarySocketPath}" "${ownerSocketPath}" "${storePath}" 384 None)'';
  startDaemon = pkgs.writeShellScript "persona-spirit-daemon-start" ''
    exec ${daemon}/bin/persona-spirit-daemon '${configuration}'
  '';
  commandLine = pkgs.writeShellScriptBin "spirit" ''
    export PERSONA_SPIRIT_SOCKET="''${PERSONA_SPIRIT_SOCKET:-${ordinarySocketPath}}"
    export PERSONA_SPIRIT_OWNER_SOCKET="''${PERSONA_SPIRIT_OWNER_SOCKET:-${ownerSocketPath}}"
    exec ${upstreamCommandLine}/bin/spirit "$@"
  '';
in
mkIf size.min {
  home.packages = [ commandLine ];

  home.sessionVariables = {
    PERSONA_SPIRIT_SOCKET = ordinarySocketPath;
    PERSONA_SPIRIT_OWNER_SOCKET = ownerSocketPath;
  };

  systemd.user.sessionVariables = {
    PERSONA_SPIRIT_SOCKET = ordinarySocketPath;
    PERSONA_SPIRIT_OWNER_SOCKET = ownerSocketPath;
  };

  systemd.user.services.persona-spirit-daemon = {
    Unit = {
      Description = "Persona-spirit daemon";
    };

    Service = {
      ExecStart = "${startDaemon}";
      Restart = "on-failure";
      RestartSec = "2s";
    };

    Install.WantedBy = [ "default.target" ];
  };
}
