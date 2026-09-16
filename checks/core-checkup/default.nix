{ pkgs, inputs, ... }:
pkgs.runCommand "core-checkup-home" { } ''
  test -f ${inputs.core-checkup-source}/tools/core-checkup.mjs
  grep -q 'OnUnitActiveSec = "30min"' ${../../modules/home/profiles/min/core-checkup.nix}
  grep -q 'configPath' ${../../modules/home/profiles/min/core-checkup.nix}
  touch $out
''
