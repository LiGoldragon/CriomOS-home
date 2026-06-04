{ pkgs, inputs, ... }:
let
  lojixRun = pkgs.callPackage ../../packages/lojix-run { inherit inputs; };
in
pkgs.runCommand "lojix-run-check"
  {
    nativeBuildInputs = [
      lojixRun
      pkgs.gnugrep
    ];
  }
  ''
    set -eu

    command -v lojix-run

    work=$PWD/work
    mkdir -p "$work/bin" "$work/state"

    cat > "$work/bin/fake-lojix" <<'SH'
    #!${pkgs.runtimeShell}
    printf '/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-result\n'
    printf 'built /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-hidden\n' >&2
    SH
    chmod +x "$work/bin/fake-lojix"

    LOJIX_RUN_LOJIX_CLI="$work/bin/fake-lojix" \
    LOJIX_RUN_DIRECTORY="$work/state" \
      lojix-run '(FullOs goldragon zeus [/tmp/datom.nota] [github:LiGoldragon/CriomOS/main] Eval None None)' \
        > "$work/success.out"

    grep -F 'lojix_run=success' "$work/success.out"
    grep -F 'request_kind=FullOs' "$work/success.out"
    grep -F 'stdout_sha256=' "$work/success.out"
    grep -F 'stderr_sha256=' "$work/success.out"
    ! grep -E '/nix/store/[0-9a-z]+-' "$work/success.out"

    cat > "$work/bin/fake-lojix" <<'SH'
    #!${pkgs.runtimeShell}
    printf 'error at /nix/store/cccccccccccccccccccccccccccccccc-leaked\n' >&2
    exit 7
    SH
    chmod +x "$work/bin/fake-lojix"

    set +e
    LOJIX_RUN_LOJIX_CLI="$work/bin/fake-lojix" \
    LOJIX_RUN_DIRECTORY="$work/state" \
      lojix-run '(FullOs goldragon zeus [/tmp/datom.nota] [github:LiGoldragon/CriomOS/main] Eval None None)' \
        > "$work/failure.out"
    code=$?
    set -e
    test "$code" -eq 7
    grep -F 'lojix_run=failed' "$work/failure.out"
    grep -F '/nix/store/<hash>-leaked' "$work/failure.out"
    ! grep -F '/nix/store/cccccccccccccccccccccccccccccccc-leaked' "$work/failure.out"

    set +e
    lojix-run > "$work/no-argument.out" 2> "$work/no-argument.err"
    code=$?
    set -e
    test "$code" -eq 2
    grep -F 'takes exactly one NOTA request' "$work/no-argument.err"

    touch "$out"
  ''
