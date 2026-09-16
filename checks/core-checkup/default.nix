{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  fixtureRoster = pkgs.writeText "core-checkup-roster-fixture.json" (builtins.toJSON {
    endpoints = [ ];
    units = [ ];
    allowRestart = false;
  });
  user = {
    name = "core-checkup-closure-test";
    size = "Min";
  };
  configuration = (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs user;
      horizon = {
        node.services = [ ];
        users = [ user ];
      };
      hexis = inputs.hexis.packages.${system}.default;
    };
    modules = [
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/core-checkup.nix
      {
        home = {
          username = user.name;
          homeDirectory = "/home/${user.name}";
          stateVersion = "26.05";
        };
        criomosHome.coreCheckup = {
          enable = true;
          rosterFile = fixtureRoster;
        };
      }
    ];
  }).config;
  service = configuration.systemd.user.services.core-checkup;
  execStart = builtins.concatStringsSep "\n" (pkgs.lib.toList service.Service.ExecStart);
  execStartPre = builtins.concatStringsSep "\n" (pkgs.lib.toList service.Service.ExecStartPre);
  unitText = pkgs.writeText "core-checkup-closure.service" "${execStartPre}\n${execStart}\n";
  sourcePath = toString inputs.core-checkup-source;
  rosterPath = toString fixtureRoster;
in
assert service ? Service;
assert builtins.match ".*${rosterPath}.*" execStart != null;
assert builtins.match ".*${rosterPath}.*" execStartPre != null;
assert builtins.hasContext execStart;
assert builtins.hasContext execStartPre;
pkgs.runCommand "core-checkup-home" {
  nativeBuildInputs = [ pkgs.nodejs ];
  exportReferencesGraph = [ "unit-closure" unitText ];
} ''
  set -eu
  test -f ${inputs.core-checkup-source}/tools/core-checkup.mjs
  grep -Fx ${pkgs.lib.escapeShellArg rosterPath} unit-closure
  grep -Fx ${pkgs.lib.escapeShellArg sourcePath} unit-closure
  cat > roster.json <<'EOF'
  {"endpoints":[],"units":[],"allowRestart":false}
  EOF
  cat > policy.json <<'EOF'
  {"eventLog":{"retention":"check"},"allowRepair":false,"wake":{"enabled":false},"luna":false,"units":[]}
  EOF
  ${pkgs.nodejs}/bin/node ${inputs.core-checkup-source}/tools/core-checkup.mjs roster.json policy.json $out/events.ndjson $out/state.json
  if ${pkgs.nodejs}/bin/node ${inputs.core-checkup-source}/tools/core-checkup.mjs missing-roster.json missing-policy.json $out/missing.ndjson $out/missing-state.json; then
    exit 1
  fi
  grep -q '"kind":"config"' $out/missing.ndjson
  cat > invalid-policy.json <<'EOF'
  {"eventLog":{"retention":"check"},"allowRepair":false,"wake":{"enabled":false},"luna":false,"units":[{"name":"not-in-os-roster.service","scope":"user","allowRestart":false}]}
  EOF
  if ${pkgs.nodejs}/bin/node ${inputs.core-checkup-source}/tools/core-checkup.mjs roster.json invalid-policy.json $out/invalid.ndjson $out/invalid-state.json; then
    exit 1
  fi
  grep -q '"kind":"config"' $out/invalid.ndjson
  touch "$out"
''
