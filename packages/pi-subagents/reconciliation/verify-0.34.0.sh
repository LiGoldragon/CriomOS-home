#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/../../.." && pwd)
work_root=${PI_SUBAGENTS_RECONCILIATION_WORK_ROOT:-/tmp/pi-subagents-0.34.0-reconciliation}
pristine=$work_root/pristine
reconciled=$work_root/reconciled
upstream_revision=12a157d2a70b2f4cbc004c020c5f9213b6d8eea8

materialize() {
  rm -rf "$work_root"
  mkdir -p "$pristine"
  curl -fsSL "https://github.com/nicobailon/pi-subagents/archive/$upstream_revision.tar.gz" |
    tar -xz -C "$pristine" --strip-components=1
  cp -a "$pristine" "$reconciled"
  patch --forward --batch -d "$reconciled" -p1 < "$script_dir/0.31.0-to-0.34.0.patch"
  printf 'materialize exit=0 upstream=%s\n' "$upstream_revision"
}

ensure_materialized() {
  test -f "$pristine/package.json" && test -f "$reconciled/package.json" || materialize
}

probe() {
  local label=$1
  shift
  "$@" >/dev/null 2>&1
  local code=$?
  printf '%s=%s\n' "$label" "$code"
  return "$code"
}

expect_code() {
  local expected=$1
  shift
  set +e
  probe "$@"
  local actual=$?
  set -e
  test "$actual" -eq "$expected"
}

applicability() {
  materialize
  local patch_file patch_name probe_tree log code
  for patch_file in "$script_dir"/original-patches/*.patch; do
    patch_name=$(basename "$patch_file")
    probe_tree=$work_root/probe-$patch_name
    log=$work_root/$patch_name.log
    cp -a "$pristine" "$probe_tree"
    set +e
    patch --dry-run --forward --batch --verbose -d "$probe_tree" -p1 < "$patch_file" > "$log" 2>&1
    code=$?
    set -e
    printf '%s exit=%s\n' "$patch_name" "$code"
    grep -nE 'checking file|Hunk|Reversed|previously applied|FAILED|ignored|offset|succeeded' "$log" || true
    rm -rf "$probe_tree"
  done
  printf 'applicability exit=0\n'
}

witness() {
  local delta=${1:?delta is required}
  local state=${2:?state is required}
  ensure_materialized
  local tree
  case "$state" in
    pristine) tree=$pristine ;;
    reconciled) tree=$reconciled ;;
    *) printf 'unknown state: %s\n' "$state" >&2; return 2 ;;
  esac

  case "$delta" in
    clarify)
      expect_code 0 clarify-code rg -F 'const shouldClarify = clarify === true' "$tree/src/runs/foreground/chain-execution.ts"
      if test "$state" = pristine; then
        expect_code 1 clarify-schema rg -F 'Omitted or false runs directly' "$tree/src/extension/schemas.ts"
      else
        expect_code 0 clarify-schema rg -F 'Omitted or false runs directly' "$tree/src/extension/schemas.ts"
      fi
      ;;
    compact-skill)
      set +e
      test "$(wc -l < "$tree/skills/pi-subagents/SKILL.md")" -le 150 &&
        rg -F 'Subagents are independent Pi processes.' "$tree/skills/pi-subagents/SKILL.md" >/dev/null
      local code=$?
      set -e
      printf 'compact-skill=%s lines=%s\n' "$code" "$(wc -l < "$tree/skills/pi-subagents/SKILL.md")"
      if test "$state" = pristine; then test "$code" -eq 1; else test "$code" -eq 0; fi
      ;;
    peer-isolation)
      expect_code 0 peer-isolation bash -c "! rg -F 'import * as piCodingAgent' '$tree/src/shared/utils.ts' >/dev/null && rg -F 'resolveConfigDirNameFromPackageJson' '$tree/src/shared/utils.ts' >/dev/null"
      ;;
    stderr-compaction)
      expect_code 0 stderr-capture rg -F 'stderrPath: path.join(asyncDir, "runner.stderr.log")' "$tree/src/runs/background/async-execution.ts"
      if test "$state" = pristine; then
        expect_code 1 stderr-post-close-compaction rg -F 'compactAsyncRunnerStderrAfterClose' "$tree/src/runs/background/async-execution.ts"
      else
        expect_code 0 stderr-post-close-compaction rg -F 'compactAsyncRunnerStderrAfterClose' "$tree/src/runs/background/async-execution.ts"
      fi
      ;;
    child-extension)
      if test "$state" = pristine; then
        expect_code 1 child-package-inheritance bash -c "! rg -F 'args.push(\"--no-extensions\")' '$tree/src/runs/shared/pi-args.ts' >/dev/null"
      else
        expect_code 0 child-package-inheritance bash -c "! rg -F 'args.push(\"--no-extensions\")' '$tree/src/runs/shared/pi-args.ts' >/dev/null"
      fi
      ;;
    read-only-evidence)
      if test "$state" = pristine; then
        expect_code 1 read-only-evidence bash -c "rg -F 'allowEmptyChangeEvidence' '$tree/src/runs/shared/acceptance.ts' >/dev/null && test -f '$tree/test/unit/acceptance-read-only-evidence.test.ts'"
      else
        expect_code 0 read-only-evidence bash -c "rg -F 'allowEmptyChangeEvidence' '$tree/src/runs/shared/acceptance.ts' >/dev/null && test -f '$tree/test/unit/acceptance-read-only-evidence.test.ts'"
      fi
      ;;
    *) printf 'unknown delta: %s\n' "$delta" >&2; return 2 ;;
  esac
  printf 'witness delta=%s state=%s exit=0\n' "$delta" "$state"
}

install_dependencies() {
  local tree=$1
  (cd "$tree" && npm ci >/dev/null)
}

focused_tests() {
  ensure_materialized
  install_dependencies "$reconciled"
  set +e
  (
    cd "$reconciled"
    node --experimental-strip-types --test \
      test/unit/acceptance.test.ts \
      test/unit/acceptance-read-only-evidence.test.ts \
      test/unit/async-execution.test.ts \
      test/unit/pi-args.test.ts \
      test/integration/chain-execution.test.ts
  ) > "$work_root/focused-tests.log" 2>&1
  local code=$?
  set -e
  grep -E '^ℹ (tests|pass|fail) ' "$work_root/focused-tests.log"
  printf 'focused-tests raw-exit=%s\n' "$code"
  test "$code" -eq 0
  grep -F 'ℹ tests 108' "$work_root/focused-tests.log" >/dev/null
  grep -F 'ℹ pass 108' "$work_root/focused-tests.log" >/dev/null
  grep -F 'ℹ fail 0' "$work_root/focused-tests.log" >/dev/null
  printf 'focused-tests exit=0\n'
}

run_full_tree() {
  local state=$1
  local tree=$2
  local expected_tests=$3
  local expected_pass=$4
  install_dependencies "$tree"
  set +e
  (cd "$tree" && npm run test:all) > "$work_root/$state-test-all.log" 2>&1
  local code=$?
  set -e
  grep -E '^ℹ (tests|pass|fail) ' "$work_root/$state-test-all.log"
  printf 'full-suite state=%s raw-exit=%s\n' "$state" "$code"
  test "$code" -eq 1
  grep -F "ℹ tests $expected_tests" "$work_root/$state-test-all.log" >/dev/null
  grep -F "ℹ pass $expected_pass" "$work_root/$state-test-all.log" >/dev/null
  grep -F 'ℹ fail 3' "$work_root/$state-test-all.log" >/dev/null
  for failure in \
    'sets the child intercom session name from env during agent startup' \
    'rewrites the final child-visible prompt through before_agent_start' \
    'uses the fanout boundary through before_agent_start when fanout env is set'; do
    grep -F "$failure" "$work_root/$state-test-all.log" >/dev/null
  done
  printf 'full-suite-known-baseline state=%s exit=0 decision-state=provisional\n' "$state"
}

full_suites() {
  ensure_materialized
  run_full_tree pristine "$pristine" 981 978
  run_full_tree reconciled "$reconciled" 985 982
  printf 'full-suites exit=0 decision-state=provisional\n'
}

nix_check() {
  local expression
  expression="let flake = builtins.getFlake \"path:$repo_root\"; pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux; candidate = pkgs.callPackage $script_dir/0.34.0.nix {}; pi = flake.packages.x86_64-linux.pi; in pkgs.callPackage $script_dir/0.34.0-check.nix { inherit candidate pi; }"
  set +e
  nix build --impure --no-link --print-build-logs --expr "$expression"
  local code=$?
  set -e
  printf 'nix-package-content-rpc-check raw-exit=%s\n' "$code"
  test "$code" -eq 0
  printf 'nix-package-content-rpc-check exit=0\n'
}

all() {
  applicability
  local delta state
  for delta in clarify compact-skill peer-isolation stderr-compaction child-extension read-only-evidence; do
    for state in pristine reconciled; do
      witness "$delta" "$state"
    done
  done
  focused_tests
  full_suites
  nix_check
  printf 'all-witnesses exit=0 decision-state=provisional\n'
}

case ${1:-all} in
  materialize) materialize ;;
  applicability) applicability ;;
  witness) witness "${2:-}" "${3:-}" ;;
  focused) materialize; focused_tests ;;
  full) materialize; full_suites ;;
  nix) nix_check ;;
  all) all ;;
  *) printf 'usage: %s {materialize|applicability|witness <delta> <pristine|reconciled>|focused|full|nix|all}\n' "$0" >&2; exit 2 ;;
esac
