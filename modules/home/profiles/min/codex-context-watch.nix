{ config, lib, pkgs, ... }:
let
  cfg = config.criomosHome.codexContextWatch;
  home = config.home.homeDirectory;
  source = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/LiGoldragon/makeshift-tools/e8ac421702714aacb62599f7f90707641eee1016/codex-context-watch.clj";
    hash = "sha256-E/COdOocAQUswPnRqyZTtvsW/z5TyS3wz6DT8hdrv94=";
  };
  modelNames = [ "Astra" "Luna" "Sol" "Terra" ];
  addressPattern = "[{] (Psyche|Mind|Field) [[:alnum:]]+ (Astra|Luna|Sol|Terra) [}]";
  addressModel = address: builtins.elemAt (builtins.match addressPattern address) 1;
  codexHome = config.criomosHome.codexPlain.homeDirectory;
  migrationHomes = lib.unique (builtins.filter (path: path != codexHome) cfg.additionalHomes);
  unitName = address: "codex-refresh-watch-" + builtins.replaceStrings [ "{ " " }" " " ] [ "" "" "-" ] address;
  start = pkgs.writeShellApplication {
    name = "codex-context-watch";
    runtimeInputs = [ pkgs.babashka pkgs.inotify-tools config.criomosHome.herdr.package ];
    text = ''
      export PATH=${lib.escapeShellArg "${home}/.local/bin"}:"$PATH"
      homes=(--home ${lib.escapeShellArg codexHome})
      for directory in ${lib.escapeShellArgs migrationHomes}; do
        if [[ -d "$directory/sessions" ]]; then homes+=(--home "$directory"); fi
      done
      exec bb ${source} "$1" "$2" \
        --margin "$3" --model-window "$4" --receipt-file "$STATE_DIRECTORY/receipts.edn" "''${homes[@]}"
    '';
  };
in
{
  options.criomosHome.codexContextWatch = {
    addresses = lib.mkOption {
      type = lib.types.listOf (lib.types.strMatching addressPattern);
      default = [ ];
      description = "Addresses covered by the Codex rollout watcher.";
    };
    modelPolicies = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs modelNames (model: lib.mkOption {
          description = "Effective Codex window and reminder thresholds for ${model}.";
          type = lib.types.submodule {
            options = {
              effectiveContextWindow = lib.mkOption { type = lib.types.ints.positive; };
              refreshInputTokens = lib.mkOption { type = lib.types.ints.positive; };
              escalationInputTokens = lib.mkOption { type = lib.types.ints.positive; };
            };
          };
        });
      };
      description = "Refresh and escalation limits for the four OpenAI models.";
    };
    additionalHomes = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Existing Codex rollout homes to follow during a launcher transition.";
    };
  };

  config = lib.mkIf (config.criomosHome.flow.enable && config.criomosHome.codexPlain.enable) {
    systemd.user.services = builtins.listToAttrs (map (address:
      let policy = cfg.modelPolicies.${addressModel address};
      in assert policy.refreshInputTokens < policy.escalationInputTokens;
         assert policy.escalationInputTokens < policy.effectiveContextWindow;
      rec {
      name = unitName address;
      value = {
        Unit = {
          Description = "Codex context refresh watcher for ${address}";
          After = [ "herdr-server.service" ];
          StartLimitIntervalSec = 0;
        };
        Service = {
          ExecStart = ''${start}/bin/codex-context-watch "${address}" ${toString policy.refreshInputTokens} ${toString (policy.escalationInputTokens - policy.refreshInputTokens)} ${toString policy.effectiveContextWindow}'';
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
