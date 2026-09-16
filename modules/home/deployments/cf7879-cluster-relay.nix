{ config, lib, pkgs, inputs, user, ... }:
let
  inherit (lib) mkEnableOption mkIf mkOption types;
  system = pkgs.stdenv.hostPlatform.system;
  messagePackage = inputs.message.packages.${system}.default;
  claudePackage = config.criomos.corePackages.claude;
  promptRelay = pkgs.writeShellApplication {
    name = "prompt-relay";
    runtimeInputs = [ pkgs.nodejs claudePackage ];
    text = ''
      exec ${pkgs.nodejs}/bin/node ${inputs.prompt-relay-source}/tools/prompt-relay "$@"
    '';
  };
  members = "cf7879@01a0a715-2d5d-7342-b278-1dbcf78795bd,efa157@efa15708-dc5d-42ce-af62-8ffb84c9815e,57a7aa@57a7aa02-e52d-4266-8746-6770ff770d11";
  unknownRoutes = pkgs.writeText "cf7879-cluster-relay-routes.json" (builtins.toJSON {
    routes = [
      { flow_identifier = "cf7879"; session_identifier = "01a0a715-2d5d-7342-b278-1dbcf78795bd"; harness = "codex"; readiness = "unknown"; endpoint = "${config.home.homeDirectory}/.codex/app-server-control/app-server-control.sock"; }
      { flow_identifier = "efa157"; session_identifier = "efa15708-dc5d-42ce-af62-8ffb84c9815e"; harness = "claude"; readiness = "unknown"; endpoint = "${promptRelay}/bin/prompt-relay"; }
      { flow_identifier = "57a7aa"; session_identifier = "57a7aa02-e52d-4266-8746-6770ff770d11"; harness = "claude"; readiness = "unknown"; endpoint = "${promptRelay}/bin/prompt-relay"; }
    ];
  });
  routeFile = if config.criomosHome.clusterRelay.runtimeRouteFile == null then unknownRoutes else config.criomosHome.clusterRelay.runtimeRouteFile;
  relay = pkgs.writeShellApplication {
    name = "cluster-relay";
    runtimeInputs = [ messagePackage ];
    text = ''
      if [ "$#" -ne 2 ]; then
        echo "usage: cluster-relay FIRST-SIX-WORDS LAST-SIX-WORDS" >&2
        exit 2
      fi
      case "''${FLOW_ID-}" in
        cf7879)
          export RELAY_SESSION_ID=01a0a715-2d5d-7342-b278-1dbcf78795bd
          export RELAY_TRANSCRIPT=${config.home.homeDirectory}/.codex/sessions/2026/09/15/rollout-2026-09-15T23-59-38-01a0a715-2d5d-7342-b278-1dbcf78795bd.jsonl
          ;;
        efa157)
          export RELAY_SESSION_ID=efa15708-dc5d-42ce-af62-8ffb84c9815e
          export RELAY_TRANSCRIPT=${config.home.homeDirectory}/.claude/projects/-home-li-wt-github-com-LiGoldragon-primary-claude-successor-840e42-bootstrap-local--claude-worktrees-claude-successor-840e42/efa15708-dc5d-42ce-af62-8ffb84c9815e.jsonl
          ;;
        57a7aa)
          export RELAY_SESSION_ID=57a7aa02-e52d-4266-8746-6770ff770d11
          export RELAY_TRANSCRIPT=${config.home.homeDirectory}/.claude/projects/-git-github-com-LiGoldragon-secondary/57a7aa02-e52d-4266-8746-6770ff770d11.jsonl
          ;;
        *)
          echo "cluster-relay: FLOW_ID is not a configured cf7879 member" >&2
          exit 2
          ;;
      esac
      export RELAY_CLUSTER_MEMBERS=${members}
      export RELAY_FLOW_ROUTES=${routeFile}
      exec relay "$@"
    '';
  };
in {
  options.criomosHome.clusterRelay = {
    enable = mkEnableOption "the cf7879 deployment snapshot for cluster-relay";
    runtimeRouteFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "A Flow-owned, freshly witnessed route JSON file. Null uses the immutable unknown-only route file, which makes every delivery unavailable.";
    };
  };
  config = mkIf config.criomosHome.clusterRelay.enable {
    home.packages = [ relay promptRelay ];
  };
}
