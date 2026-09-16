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
  policy = builtins.fromJSON configuration.xdg.configFile."core-checkup/policy.json".text;
  execStart = builtins.concatStringsSep "\n" (pkgs.lib.toList service.Service.ExecStart);
  execStartPre = builtins.concatStringsSep "\n" (pkgs.lib.toList service.Service.ExecStartPre);
  execStopPost = builtins.concatStringsSep "\n" (pkgs.lib.toList service.Service.ExecStopPost);
  unitText = pkgs.writeText "core-checkup-closure.service" "${execStartPre}\n${execStart}\n${execStopPost}\n";
  sourcePath = toString inputs.core-checkup-source;
  rosterPath = toString fixtureRoster;
  missingPreflight = pkgs.writeText "core-checkup-missing-roster-preflight" (builtins.replaceStrings
    [ rosterPath "%S/core-checkup/events.ndjson" ]
    [ "$out/missing-roster.json" "$out/preflight.ndjson" ]
    execStartPre);
  resultFixture = pkgs.writeText "core-checkup-service-result-fixture" (builtins.replaceStrings
    [ "%S/core-checkup/events.ndjson" ]
    [ "$out/results.ndjson" ]
    execStopPost);
in
assert service ? Service;
assert service.Service.TimeoutStartSec == "180s";
assert service.Service.KillMode == "control-group";
assert service.Service.WorkingDirectory == "%t/core-checkup";
assert service.Service.StateDirectoryMode == "0700";
assert !(service.Service ? RuntimeMaxSec);
assert policy.luna == false;
assert builtins.elem fixtureRoster.drvPath (builtins.attrNames (builtins.getContext execStart));
assert builtins.elem fixtureRoster.drvPath (builtins.attrNames (builtins.getContext execStartPre));
pkgs.runCommand "core-checkup-home" {
  nativeBuildInputs = [ pkgs.nodejs pkgs.util-linux pkgs.bash ];
  exportReferencesGraph = [ "unit-closure" unitText ];
} ''
  set -eu
  test -f ${inputs.core-checkup-source}/tools/core-checkup.mjs
  grep -Fx ${pkgs.lib.escapeShellArg rosterPath} unit-closure
  grep -Fx ${pkgs.lib.escapeShellArg sourcePath} unit-closure
  if ${pkgs.bash}/bin/bash ${missingPreflight}; then
    exit 1
  fi
  SERVICE_RESULT=timeout EXIT_CODE=killed EXIT_STATUS=9 ${pkgs.bash}/bin/bash ${resultFixture}
  SERVICE_RESULT=oom-kill EXIT_CODE=killed EXIT_STATUS=9 ${pkgs.bash}/bin/bash ${resultFixture}
  SERVICE_RESULT=exit-code EXIT_CODE=exited EXIT_STATUS=1 ${pkgs.bash}/bin/bash ${resultFixture}
  SERVICE_RESULT='bad"result' EXIT_CODE=bad EXIT_STATUS=00 ${pkgs.bash}/bin/bash ${resultFixture}
  SERVICE_RESULT=timeout EXIT_CODE=killed EXIT_STATUS=999999999999999999999999 ${pkgs.bash}/bin/bash ${resultFixture}
  ${pkgs.nodejs}/bin/node - "$out/preflight.ndjson" "$out/results.ndjson" <<'NODE'
  const assert = require("node:assert/strict");
  const fs = require("node:fs");
  const decode = (path) => fs.readFileSync(path, "utf8").trim().split("\n").map(JSON.parse);
  const [preflight] = decode(process.argv[2]);
  assert.deepEqual(
    { schema: preflight.schema, kind: preflight.kind, name: preflight.name, status: preflight.status, reason: preflight.reason },
    { schema: "core-checkup/v1", kind: "config", name: "core-checkup", status: "config_missing", reason: "roster_unreadable" },
  );
  assert.match(preflight.at, /^\d{4}-\d{2}-\d{2}T/);
  const results = decode(process.argv[3]);
  assert.deepEqual(
    results.map(({ kind, name, status, service_result, exit_code, exit_status }) => ({ kind, name, status, service_result, exit_code, exit_status })),
    [
      { kind: "service-result", name: "core-checkup", status: "global_timeout", service_result: "timeout", exit_code: "killed", exit_status: 9 },
      { kind: "service-result", name: "core-checkup", status: "oom_kill", service_result: "oom-kill", exit_code: "killed", exit_status: 9 },
      { kind: "service-result", name: "core-checkup", status: "service_exit_code", service_result: "exit-code", exit_code: "exited", exit_status: 1 },
      { kind: "service-result", name: "core-checkup", status: "service_failure", service_result: "unknown", exit_code: "unknown", exit_status: null },
      { kind: "service-result", name: "core-checkup", status: "global_timeout", service_result: "timeout", exit_code: "killed", exit_status: null },
    ],
  );
  assert.equal(results.every((event) => /^\d{4}-\d{2}-\d{2}T/.test(event.at)), true);
  NODE
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
