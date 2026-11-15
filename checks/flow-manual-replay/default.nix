{ pkgs, inputs, ... }:
let
  inherit (pkgs) lib;
  system = pkgs.stdenv.hostPlatform.system;
  user = { name = "replay-test"; size = "Min"; capabilities = [ "AgentStack" ]; };
  runtime = pkgs.runCommand "flow-replay-fixture" { } ''
    mkdir -p "$out/bin"
    cat > "$out/bin/flow-meta" <<'SCRIPT'
#!${pkgs.runtimeShell}
set -eu
: "''${REPLAY_LOG:?}"
printf '%s\n' "$1" | ${pkgs.coreutils}/bin/head -n1 | ${pkgs.coreutils}/bin/cut -d. -f2 >> "$REPLAY_LOG"
count=$(${pkgs.coreutils}/bin/wc -l < "$REPLAY_LOG")
if [ "$count" = "''${REPLAY_FAIL_AT:-0}" ]; then
  printf 'Refused.Fixture\n'
else
  printf 'Configured.Fixture\n'
fi
SCRIPT
    chmod +x "$out/bin/flow-meta"
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
      ({ lib, ... }: {
        options.criomosHome.herdr.stableCodexClientPackage = lib.mkOption { default = runtime; };
        options.criomosHome.codexNextCandidate = lib.mkOption {
          default = { hash = "fixture"; clientPackage = runtime; package = runtime; };
        };
      })
      {
        home.username = user.name;
        home.homeDirectory = "/home/${user.name}";
        home.stateVersion = "26.05";
        criomosHome.flow0550.sendServers = [ ];
      }
    ];
  }).config;
  replay = configuration.criomosHome.flow0550.replayPackage;
  services = configuration.systemd.user.services;
  expectedUnit = {
    Unit = {
      Description = "Flow Nexus 0.55.0 at main";
      Wants = [ "curriculum-nexus.service" ];
      After = [ "curriculum-nexus.service" "systemd-tmpfiles-setup.service" ];
    };
    Service = {
      Environment = [ ];
      Type = "notify";
      WorkingDirectory = "%h";
      ExecStart = [ "${runtime}/bin/flow-nexus-daemon main" ];
      Restart = "on-failure";
      RestartSec = "100ms";
      MemoryMax = "3G";
      MemorySwapMax = "0";
    };
    Install.WantedBy = [ "default.target" ];
  };
in
assert !(services ? flow-configure-0550);
assert services.flow-nexus-0550 == expectedUnit;
assert builtins.length replay.queryFiles == 10;
assert builtins.elem replay configuration.home.packages;
pkgs.runCommand "flow-manual-replay-contract" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  export REPLAY_LOG="$TMPDIR/queries"
  mkdir -p "$XDG_RUNTIME_DIR"
  replay=${replay}/bin/flow-replay-0.55.0
  "$replay" > "$TMPDIR/success"
  cat > "$TMPDIR/expected" <<'EXPECTED'
Nexus
Models
Thresholds
SendServers
HarnessHook
Metaflows
HarnessFlags
Investigation
DefaultMinutes
HandoverPolicies
EXPECTED
  diff -u "$TMPDIR/expected" "$REPLAY_LOG"
  test "$(wc -l < "$TMPDIR/success")" = 10
  : > "$REPLAY_LOG"
  export REPLAY_FAIL_AT=3
  if "$replay" > "$TMPDIR/refused" 2>&1; then exit 1; fi
  test "$(wc -l < "$REPLAY_LOG")" = 3
  grep -F Refused.Fixture "$TMPDIR/refused"
  : > "$REPLAY_LOG"
  if "$replay" next > "$TMPDIR/argument" 2>&1; then exit 1; fi
  test ! -s "$REPLAY_LOG"
  if env -u XDG_RUNTIME_DIR "$replay" > "$TMPDIR/environment" 2>&1; then exit 1; fi
  test ! -s "$REPLAY_LOG"
  mkdir "$out"
  cp "$TMPDIR/success" "$TMPDIR/refused" "$out/"
''
