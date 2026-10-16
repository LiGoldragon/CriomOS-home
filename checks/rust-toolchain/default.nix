{ inputs, pkgs, ... }:

let
  rustToolchain = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
  sentinel = pkgs.runCommand "rust-toolchain-sentinel" { } ''
    mkdir -p "$out/bin" "$out/lib/rustlib/src"
    for name in ${pkgs.lib.concatStringsSep " " rustToolchain.guardedCommands}; do
      cat > "$out/bin/$name" <<'SCRIPT'
    #!${pkgs.runtimeShell}
    touch "$LOCAL_COMPILER_SENTINEL"
    exit 99
    SCRIPT
      chmod +x "$out/bin/$name"
    done
    ln -s ${pkgs.coreutils}/bin/true "$out/bin/rustfmt"
  '';
  client = rustToolchain.withRaw sentinel;
in
pkgs.runCommand "rust-toolchain-check" { nativeBuildInputs = [ client ]; } ''
  set -eu
  export LOCAL_COMPILER_SENTINEL="$PWD/compiler-was-run"
  for command in ${pkgs.lib.concatStringsSep " " rustToolchain.guardedCommands}; do
    for action in build test check run doc install clippy fmt --version --help unknown-plugin; do
      status=0
      "$command" "$action" >reply 2>&1 || status=$?
      test "$status" -eq 126
      grep -F 'configured remote builder' reply
      test ! -e "$LOCAL_COMPILER_SENTINEL"
    done
    status=0
    CARGO_HOME="$PWD/override" RUSTC=${sentinel}/bin/rustc \
      "$command" +stable --config build.rustc=${sentinel}/bin/rustc build >reply 2>&1 || status=$?
    test "$status" -eq 126
    test ! -e "$LOCAL_COMPILER_SENTINEL"
  done
  rustfmt
  test ! -e "$LOCAL_COMPILER_SENTINEL"
  printf '[build]\njobs = 2\n\n' >legacy.toml
  ${rustToolchain.retireLegacyConfig}/bin/retire-managed-local-cargo-jobs "$PWD/legacy.toml"
  test ! -e legacy.toml
  printf '[build]\njobs = 2\n\n[net]\noffline = true\n' >custom.toml
  cp custom.toml custom.before
  ${rustToolchain.retireLegacyConfig}/bin/retire-managed-local-cargo-jobs "$PWD/custom.toml"
  cmp custom.toml custom.before
  ln -s custom.toml symbolic.toml
  ${rustToolchain.retireLegacyConfig}/bin/retire-managed-local-cargo-jobs "$PWD/symbolic.toml"
  test -L symbolic.toml
  touch "$out"
''
