{ inputs, pkgs, ... }:

let
  whisrs = pkgs.callPackage ../../packages/whisrs { inherit inputs; };
in
pkgs.runCommand "whisrs-recall-smoke" { } ''
  set -eu

  selector_dir="$TMPDIR/bin"
  selector="$selector_dir/fuzzel"
  copy="$TMPDIR/fake-copy"
  history="$TMPDIR/history.jsonl"
  copied="$TMPDIR/copied.txt"

  mkdir -p "$selector_dir"

  cat > "$selector" <<'EOF'
  #!${pkgs.runtimeShell}
  set -eu
  test "$1" = "--dmenu"
  test "$2" = "--prompt"
  test "$3" = "whisrs> "
  test "$4" = "--width=120"
  test "$5" = "--with-nth=2"
  test "$6" = "--accept-nth=1"
  test "$7" = "--match-nth=2"
  test "$8" = "--only-match"
  cat > "$TMPDIR/selector-input.txt"
  sed -n '1p' "$TMPDIR/selector-input.txt" | ${pkgs.coreutils}/bin/cut -f1
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

  PATH="$selector_dir:$PATH" ${whisrs}/bin/whisrs-recall \
    --history "$history" \
    --copy-command "$copy" \
    --print > "$TMPDIR/stdout.txt"

  printf 'newer transcript\nwith newline' > "$TMPDIR/expected-copy.txt"
  printf 'newer transcript\nwith newline\n' > "$TMPDIR/expected-stdout.txt"
  cmp "$copied" "$TMPDIR/expected-copy.txt"
  cmp "$TMPDIR/stdout.txt" "$TMPDIR/expected-stdout.txt"
  printf '1\tnewer transcript with newline\n2\tolder transcript\n' > "$TMPDIR/expected-selector-input.txt"
  cmp "$TMPDIR/selector-input.txt" "$TMPDIR/expected-selector-input.txt"
  ! grep -F '2026-05-11' "$TMPDIR/selector-input.txt"

  touch "$out"
''
