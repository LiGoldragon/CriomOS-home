{ pkgs, inputs, ... }:
pkgs.runCommand "core-checkup-home" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  test -f ${inputs.core-checkup-source}/tools/core-checkup.mjs
  grep -q 'OnUnitActiveSec = "30min"' ${../../modules/home/profiles/min/core-checkup.nix}
  grep -q 'rosterFile' ${../../modules/home/profiles/min/core-checkup.nix}
  grep -q 'policyFile' ${../../modules/home/profiles/min/core-checkup.nix}
  grep -q 'wake.enabled = false' ${../../modules/home/profiles/min/core-checkup.nix}
  grep -q 'd3002f4bf9ae81852c3b7e5e65f4793afbc1e3da' ${../../flake.nix}
  grep -q 'ExecStartPre.*test -r.*rosterFile' ${../../modules/home/profiles/min/core-checkup.nix}
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
  touch $out
''
