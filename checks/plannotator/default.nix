{ pkgs, ... }:
let
  plannotator = pkgs.callPackage ../../packages/plannotator { };
in
pkgs.runCommand "plannotator-cli-contract"
  {
    nativeBuildInputs = [
      plannotator
      pkgs.curl
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    document="$TMPDIR/review.md"
    result="$TMPDIR/result.json"
    printf '%s\n' '# Review this plan' > "$document"

    BROWSER=true PLANNOTATOR_DATA_DIR="$TMPDIR/data" PLANNOTATOR_PORT=19432 \
      plannotator annotate "$document" --gate --json --require-approval --result-file "$result" \
      > "$TMPDIR/stdout" 2> "$TMPDIR/stderr" &
    annotate_pid=$!

    if ! curl --silent --show-error --fail --retry 10 --retry-connrefused --retry-delay 1 \
      http://127.0.0.1:19432/api/plan > "$TMPDIR/plan.json"; then
      cat "$TMPDIR/stderr" >&2
      kill "$annotate_pid" 2>/dev/null || true
      wait "$annotate_pid" || true
      exit 1
    fi
    grep -F '"mode":"annotate"' "$TMPDIR/plan.json"
    grep -F '"gate":true' "$TMPDIR/plan.json"
    curl --silent --show-error --fail \
      --header 'content-type: application/json' \
      --data '{"feedback":"Needs a CLI roundtrip","annotations":[]}' \
      http://127.0.0.1:19432/api/feedback > "$TMPDIR/feedback.json"
    grep -Fx '{"ok":true}' "$TMPDIR/feedback.json"

    set +e
    wait "$annotate_pid"
    status=$?
    set -e
    test "$status" -eq 1
    expected='{"decision":"annotated","feedback":"Needs a CLI roundtrip"}'
    test "$(cat "$TMPDIR/stdout")" = "$expected"
    test "$(cat "$result")" = "$expected"

    plannotator --version >/dev/null
    plannotator annotate --help > "$TMPDIR/annotate-help"
    grep -F -- '--tailscale' "$TMPDIR/annotate-help"
    grep -F -- '--gate' "$TMPDIR/annotate-help"
    grep -F -- '--json' "$TMPDIR/annotate-help"
    grep -F -- '--require-approval' "$TMPDIR/annotate-help"
    grep -F -- '--result-file' "$TMPDIR/annotate-help"

    set +e
    plannotator annotate "$TMPDIR/missing.md" --gate --json --require-approval >/dev/null 2>&1
    status=$?
    set -e
    test "$status" -eq 2

    touch "$out"
  ''
