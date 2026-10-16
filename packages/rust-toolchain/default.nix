{ inputs, pkgs, ... }:
let
  raw = (inputs.rust-overlay.lib.mkRustBin { } pkgs).stable."1.97.1".minimal.override {
    extensions = [
      "rust-src"
      "rust-analyzer"
      "rustfmt"
      "clippy"
    ];
  };
  guardedCommands = [
    "cargo"
    "rustc"
    "rustdoc"
    "cargo-clippy"
    "clippy-driver"
    "rust-analyzer"
    "rustup"
    "cargo-fmt"
  ];
  guards = map (
    name:
    pkgs.writeShellScriptBin name ''
      printf '%s\n' '${name}: local compilation is disabled; use the repository Nix package/check selector on the configured remote builder. Use rustfmt for explicit formatting.' >&2
      exit 126
    ''
  ) guardedCommands;
  legacyCargoConfig = pkgs.writeText "legacy-local-cargo-config.toml" "[build]\njobs = 2\n\n";
  retireLegacyConfig = pkgs.writeShellApplication {
    name = "retire-managed-local-cargo-jobs";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      file="''${1:?Cargo config path required}"
      if [ -f "$file" ] && [ ! -L "$file" ] && cmp -s ${legacyCargoConfig} "$file"; then
        rm -- "$file"
      fi
    '';
  };
  withRaw =
    toolchain:
    pkgs.runCommand "rust-toolchain-remote-only"
      {
        passthru = {
          raw = toolchain;
          inherit guardedCommands retireLegacyConfig withRaw;
        };
      }
      ''
        mkdir -p "$out/bin" "$out/lib/rustlib"
        ${pkgs.lib.concatMapStringsSep "\n" (guard: ''ln -s ${guard}/bin/* "$out/bin/"'') guards}
        ln -s ${toolchain}/bin/rustfmt "$out/bin/rustfmt"
        ln -s ${toolchain}/lib/rustlib/src "$out/lib/rustlib/src"
      '';
in
withRaw raw
