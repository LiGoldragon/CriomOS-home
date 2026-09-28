{ pkgs, inputs, ... }:
let
  user = { name = "li"; size = "Min"; };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs user; };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/herdr.nix
        ../../modules/home/profiles/min/flow.nix
        {
          home.username = user.name;
          home.homeDirectory = "/home/li";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  herdrPackage = configuration.criomosHome.herdr.package;
  stableClient = configuration.criomosHome.herdr.stableCodexClientPackage;
  nextRaw = configuration.criomosHome.codexNext.rawClientPackage;
  nextClient = configuration.criomosHome.codexNext.clientPackage;
  nextRemoteClient = configuration.criomosHome.codexNext.remoteClientPackage;
  flowEnvironment = configuration.systemd.user.services.flow-nexus.Service.Environment;
  configToml = builtins.readFile configuration.xdg.configFile."herdr/config.toml".source;
in
assert builtins.match ".*codex_executables.*codex-stable-flow-client.*codex-next-flow-client.*" configToml != null;
assert builtins.elem "FLOW_CODEX_STABLE_CLIENT=${stableClient}/bin/codex-stable-flow-client" flowEnvironment;
assert builtins.elem "FLOW_CODEX_STABLE_SOCKET=/home/li/.codex/app-server-control/app-server-control.sock" flowEnvironment;
assert builtins.elem "FLOW_CODEX_STABLE_HOME=/home/li/.codex" flowEnvironment;
assert builtins.elem "FLOW_CODEX_STABLE_MODELS=gpt-5.6-terra,gpt-5.6-sol,gpt-5.6-luna" flowEnvironment;
assert builtins.elem "FLOW_CODEX_NEXT_CLIENT=${nextClient}/bin/codex-next-flow-client" flowEnvironment;
assert builtins.elem "FLOW_CODEX_NEXT_SOCKET=/home/li/.codex-next/app-server-control/app-server-control.sock" flowEnvironment;
assert builtins.elem "FLOW_CODEX_NEXT_HOME=/home/li/.codex-next" flowEnvironment;
assert builtins.elem "FLOW_CODEX_NEXT_MODELS=gpt-6-sol,gpt-6-luna,gpt-6-astra" flowEnvironment;
pkgs.runCommand "herdr-agent-executable-contract" { } ''
  set -eu
  stable=${stableClient}/bin/codex-stable-flow-client
  next=${nextClient}/bin/codex-next-flow-client
  remote=${nextRemoteClient}/bin/codex-next

  grep -F 'export CODEX_HOME=' "$stable"
  grep -F 'exec ${configuration.criomos.corePackages.codex}/bin/codex "$@"' "$stable"
  ! grep -F -- '--remote' "$stable"
  grep -F 'export CODEX_HOME=' "$next"
  grep -F 'exec ${nextRaw}/bin/codex "$@"' "$next"
  ! grep -F -- '--remote' "$next"
  grep -F -- '--remote' "$remote"

  ${herdrPackage}/bin/herdr --help | grep -F 'agent <subcommand>'
  mkdir -p "$out"
  cp ${configuration.xdg.configFile."herdr/config.toml".source} "$out/config.toml"
''
