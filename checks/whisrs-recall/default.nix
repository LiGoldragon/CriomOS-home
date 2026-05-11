{ inputs, pkgs, ... }:

let
  whisrs = pkgs.callPackage ../../packages/whisrs { inherit inputs; };
in
pkgs.runCommand "whisrs-recall-smoke" { } ''
  set -eu

  selector="$TMPDIR/fake-fuzzel"
  copy="$TMPDIR/fake-copy"
  history="$TMPDIR/history.jsonl"
  copied="$TMPDIR/copied.txt"

  cat > "$selector" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  test "$1" = "--dmenu"
  test "$2" = "--prompt"
  test "$3" = "whisrs> "
  cat > "$TMPDIR/selector-input.txt"
  sed -n '1p' "$TMPDIR/selector-input.txt"
  EOF
  chmod +x "$selector"

  cat > "$copy" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  cat > "$TMPDIR/copied.txt"
  EOF
  chmod +x "$copy"

  cat > "$history" <<'EOF'
  {"timestamp":"2026-05-11T09:00:00+00:00","text":"older transcript","backend":"openai","language":"en","duration_secs":1.0}
  {"timestamp":"2026-05-11T10:00:00+00:00","text":"newer transcript\nwith newline","backend":"openai","language":"en","duration_secs":2.0}
  EOF

  ${whisrs}/bin/whisrs-recall \
    --history "$history" \
    --selector "$selector" \
    --selector-arg=--dmenu \
    --selector-arg=--prompt \
    --selector-arg='whisrs> ' \
    --copy-command "$copy" \
    --print > "$TMPDIR/stdout.txt"

  printf 'newer transcript\nwith newline' > "$TMPDIR/expected-copy.txt"
  printf 'newer transcript\nwith newline\n' > "$TMPDIR/expected-stdout.txt"
  cmp "$copied" "$TMPDIR/expected-copy.txt"
  cmp "$TMPDIR/stdout.txt" "$TMPDIR/expected-stdout.txt"
  grep -F 'newer transcript with newline' "$TMPDIR/selector-input.txt"
  grep -F 'older transcript' "$TMPDIR/selector-input.txt"

  touch "$out"
''
