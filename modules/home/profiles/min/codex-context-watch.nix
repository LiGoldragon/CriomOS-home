{ config, lib, pkgs, ... }:
let
  cfg = config.criomosHome.codexContextWatch;
  home = config.home.homeDirectory;
  source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/LiGoldragon/makeshift-tools/9952ef331e9288e47dbaabfdab5e7e10eb093b7e/codex-context-watch.clj";
    hash = "sha256-burxSEn8AYerq6ky+FHTnDI5yBjudn9+x71VJQrhu2M=";
  };
  unitName = address: "codex-refresh-watch-" + builtins.replaceStrings [ "{ " " }" " " ] [ "" "" "-" ] address;
  start = pkgs.writeShellApplication {
    name = "codex-context-watch";
    runtimeInputs = [ pkgs.babashka pkgs.inotify-tools config.criomosHome.herdr.package ];
    text = ''
      export PATH=${lib.escapeShellArg "${home}/.local/bin"}:"$PATH"
      homes=(--home ${lib.escapeShellArg config.criomosHome.codexPlain.homeDirectory})
      for directory in ${lib.escapeShellArgs cfg.additionalHomes}; do
        if [[ -d "$directory/sessions" ]]; then homes+=(--home "$directory"); fi
      done
      exec bb ${source} "$1" ${toString cfg.inputTokenThreshold} \
        --margin ${toString cfg.escalationMargin} --receipt-file "$STATE_DIRECTORY/receipts.edn" "''${homes[@]}"
    '';
  };
in
{
  options.criomosHome.codexContextWatch = {
    addresses = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching "[{] (Psyche|Mind|Field) [[:alnum:]]+ Sol [}]");
      default = [ ];
      description = "Sol addresses covered by the Codex rollout watcher.";
    };
    inputTokenThreshold = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Input tokens at which the watcher asks for a handover and refresh.";
    };
    escalationMargin = lib.mkOption {
      type = lib.types.ints.positive;
      description = "Additional input tokens at which the watcher sends the urgent reminder.";
    };
    additionalHomes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Existing Codex rollout homes to follow during a launcher transition.";
    };
  };

  config = lib.mkIf (config.criomosHome.flow.enable && config.criomosHome.codexPlain.enable) {
    systemd.user.services = builtins.listToAttrs (map (address: rec {
      name = unitName address;
      value = {
        Unit = {
          Description = "Codex context refresh watcher for ${address}";
          After = [ "herdr-server.service" ];
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = ''${start}/bin/codex-context-watch "${address}"'';
          Restart = "on-failure";
          RestartSec = "5s";
          StateDirectory = name;
          StateDirectoryMode = "0700";
          UMask = "0077";
        };
        Install.WantedBy = [ "default.target" ];
      };
    }) cfg.addresses);
  };
}
