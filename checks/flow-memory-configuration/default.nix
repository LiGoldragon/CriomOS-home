{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  user = { name = "memory-test"; size = "Min"; capabilities = [ "AgentStack" ]; };
  runtime = pkgs.runCommand "flow-memory-fixture" { } ''
    mkdir -p "$out/bin"
    for client in flow flow-meta; do
      cat > "$out/bin/$client" <<'SCRIPT'
#!${pkgs.runtimeShell}
set -eu
printf '%s\n' "$XDG_CONFIG_HOME"
printf '%s\n' "$*"
SCRIPT
      chmod +x "$out/bin/$client"
    done
    touch "$out/bin/flow-hook" "$out/bin/flow-nexus-daemon"
  '';
  fixtureInputs = inputs // {
    flow-0550.packages.${system} = { default = runtime; nexus-configure = runtime; };
  };
  configuration = (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inputs = fixtureInputs; inherit user; };
    modules = [
      ../../modules/home/profiles/min/nexus-places.nix
      ../../modules/home/profiles/min/flow-0550.nix
      {
        home.username = user.name;
        home.homeDirectory = "/home/${user.name}";
        home.stateVersion = "26.05";
        criomosHome.flow0550.heapProfile = null;
      }
    ];
  }).config;
  deployment = configuration.criomosHome.flow0550;
  authored = (import ../../modules/home/profiles/min/flow-nexus-place.nix {
    version = "0.55.0"; slug = "0550";
  }) { config = configuration; inputs = fixtureInputs; inherit lib pkgs user; };
  expectedUnit = {
    Unit = {
      Description = "Flow Nexus 0.55.0 at main";
      Wants = [ "curriculum-nexus.service" ];
      After = [ "curriculum-nexus.service" "systemd-tmpfiles-setup.service" ];
    };
    Service = {
      Type = "notify";
      WorkingDirectory = "%h";
      ExecStart = "${runtime}/bin/flow-nexus-daemon main";
      Restart = "on-failure";
      RestartSec = "100ms";
      MemoryMax = "3G";
      MemorySwapMax = "0";
    };
    Install.WantedBy = [ "default.target" ];
  };
  policyOptions = [
    "declarationDirectory" "ownerDeclarations" "configurationDirectory"
    "trailingConfigurationFiles" "sendServers" "messageNexus"
    "presentationPrompt" "herdrSession" "replayPackage"
  ];
  moduleSource = builtins.readFile ../../modules/home/profiles/min/flow-nexus-place.nix;
  profileSource = builtins.readFile ../../modules/home/profiles/min/flow-0550.nix;
in
assert authored.config.content.systemd.user.services == { flow-nexus-0550 = expectedUnit; };
assert configuration.systemd.user.services.flow-nexus-0550.Unit.X-SwitchMethod == "keep-old";
assert authored.config.content.home.packages == [ deployment.clients ];
assert builtins.attrNames authored.config.content.home.file.content == [ ".local/bin/flow-hook" ];
assert configuration.home.file.".local/bin/flow-hook".source == "${runtime}/bin/flow-hook";
assert deployment.package == runtime;
assert lib.all (name: !(builtins.hasAttr name authored.options.criomosHome.flow0550)) policyOptions;
assert !(builtins.pathExists ../../modules/home/profiles/min/flow-nexus-config);
assert !(lib.hasInfix "Configure." moduleSource);
assert !(lib.hasInfix "flow-replay-" moduleSource);
assert !(lib.hasInfix "flow-nexus-config" profileSource);
assert !(configuration.systemd.user.services ? flow-configure-0550);
pkgs.runCommand "flow-memory-configuration-contract" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  test "$(cat ${deployment.placeConfiguration}/nexus/flow-nexus.datom)" = '{ main }'
  test "$(readlink ${deployment.placeConfiguration}/nexus/main/flow-nexus.signal)" = '/home/memory-test/.config/nexus/main/flow-nexus.signal'
  for client in flow flow-meta; do
    ${deployment.clients}/bin/"$client-0.55.0" Fixture > "$TMPDIR/$client"
    printf '%s\n' '${deployment.placeConfiguration}' Fixture > "$TMPDIR/expected"
    diff -u "$TMPDIR/expected" "$TMPDIR/$client"
  done
  test ! -e ${deployment.clients}/bin/flow-replay-0.55.0
  touch "$out"
''
