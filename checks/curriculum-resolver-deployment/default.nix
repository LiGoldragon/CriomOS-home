{ pkgs, inputs, ... }:
let
  deployment = pkgs.callPackage ../../packages/curriculum-resolver-deployment { inherit inputs; };
in pkgs.runCommand "curriculum-resolver-contract" { } ''
  set -eu
  export XDG_RUNTIME_DIR="$TMPDIR/runtime"
  ${pkgs.lib.concatMapStringsSep "\n" (value: "export " + pkgs.lib.escapeShellArg value) (deployment.environment "$TMPDIR/workspace")}
  mkdir -m 0700 -p "$XDG_RUNTIME_DIR/curriculum"
  ${deployment.runtime}/bin/curriculum-nexus > "$TMPDIR/nexus.log" 2>&1 &
  resolver_pid=$!
  trap 'kill "$resolver_pid" 2>/dev/null || true; wait "$resolver_pid" || true' EXIT
  attempts=200
  while [ ! -S "$XDG_RUNTIME_DIR/curriculum/curriculum.sock" ]; do
    if ! kill -0 "$resolver_pid" 2>/dev/null; then cat "$TMPDIR/nexus.log"; exit 1; fi
    attempts=$((attempts - 1)); test "$attempts" -gt 0
    sleep 0.05
  done
  query=$(${pkgs.babashka}/bin/bb -e '(require (quote [clojure.edn :as edn]) (quote [clojure.string :as str])) (let [m (:modules (edn/read-string (slurp (first *command-line-args*))))] (println (str "ComposeStartup.{ { Psyche core Secondary } Claude [ " (str/join " " (map name (:system m))) " ] [ " (str/join " " (map name (:user m))) " ] }")))' ${inputs.primary}/config/main-flow/psyche.edn)
  ${deployment.runtime}/bin/curriculum "$query" > "$TMPDIR/composed.datom"
  grep -q '^StartupComposed\.' "$TMPDIR/composed.datom"
  grep -q 'These are your skills, given here; do not reload them.' "$TMPDIR/composed.datom"
  ${deployment.runtime}/bin/curriculum 'ComposeRole.{ illustrator ClaudeAgent }' > "$TMPDIR/role.datom"
  grep -q '^RoleComposed\.' "$TMPDIR/role.datom"
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ spirit-core intent-main-flow ] [ /tmp/inline-context ] }' > "$TMPDIR/path.out" 2>&1; then
    echo "Curriculum admitted a path-shaped module ID" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum 'ComposeStartup.{ { Psyche core Secondary } Claude [ intent-main-flow ] [ spirit-core ] }' > "$TMPDIR/placement.out" 2>&1; then
    echo "Curriculum admitted USER spirit" >&2
    exit 1
  fi
  if ${deployment.runtime}/bin/curriculum RebuildSkills > "$TMPDIR/retired.out" 2>&1; then
    echo "Curriculum retained the retired file-projection API" >&2
    exit 1
  fi
  touch "$out"
''
