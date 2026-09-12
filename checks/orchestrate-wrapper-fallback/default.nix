{ inputs, pkgs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  orchestrateModule = ../../modules/home/profiles/min/orchestrate.nix;
  fakeOrdinaryClient = pkgs.writeShellScriptBin "orchestrate" ''
    set -eu
    : "''${ORCHESTRATE_WRAPPER_WITNESS:?}"
    : "''${ORCHESTRATE_SOCKET:?}"
    ${pkgs.coreutils}/bin/printf '%s\n' "$ORCHESTRATE_SOCKET" > "$ORCHESTRATE_WRAPPER_WITNESS"
  '';
  fakeMetaClient = pkgs.writeShellScriptBin "orchestrate-meta" ''
    set -eu
    : "''${ORCHESTRATE_WRAPPER_WITNESS:?}"
    : "''${ORCHESTRATE_META_SOCKET:?}"
    ${pkgs.coreutils}/bin/printf '%s\n' "$ORCHESTRATE_META_SOCKET" > "$ORCHESTRATE_WRAPPER_WITNESS"
  '';
  fakeOrchestratePackage = pkgs.symlinkJoin {
    name = "fake-orchestrate-nexus-clients";
    paths = [
      fakeOrdinaryClient
      fakeMetaClient
    ];
  };
  fakeOrchestrate = {
    packages.${system}.default = fakeOrchestratePackage;
  };
  moduleResult = import orchestrateModule {
    inherit pkgs;
    inputs = inputs // {
      orchestrate = fakeOrchestrate;
    };
  };
  # The module returns a plain attribute set. Its sibling
  # checks/orchestrate-service-path already carried this fallback; this file
  # did not, so it could not be evaluated at all.
  moduleConfiguration =
    if moduleResult ? config && moduleResult.config ? content then
      moduleResult.config.content
    else if moduleResult ? content then
      moduleResult.content
    else
      moduleResult;
  profilePackage = builtins.head moduleConfiguration.home.packages;
in
pkgs.runCommand "orchestrate-wrapper-fallback" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
  set -eu

  ordinary_witness="$TMPDIR/ordinary-socket"
  meta_witness="$TMPDIR/meta-socket"

  # The underlying client rejects the missing transport variable, witnessing
  # the pre-fallback boundary without depending on any running Nexus.
  if ${pkgs.coreutils}/bin/env -u XDG_RUNTIME_DIR -u ORCHESTRATE_SOCKET \
    ORCHESTRATE_WRAPPER_WITNESS="$ordinary_witness" \
    ${fakeOrchestratePackage}/bin/orchestrate; then
    exit 1
  fi
  if ${pkgs.coreutils}/bin/env -u XDG_RUNTIME_DIR -u ORCHESTRATE_META_SOCKET \
    ORCHESTRATE_WRAPPER_WITNESS="$meta_witness" \
    ${fakeOrchestratePackage}/bin/orchestrate-meta; then
    exit 1
  fi

  ${pkgs.coreutils}/bin/env -u XDG_RUNTIME_DIR \
    ORCHESTRATE_WRAPPER_WITNESS="$ordinary_witness" \
    ${profilePackage}/bin/orchestrate
  ${pkgs.coreutils}/bin/env -u XDG_RUNTIME_DIR \
    ORCHESTRATE_WRAPPER_WITNESS="$meta_witness" \
    ${profilePackage}/bin/orchestrate-meta

  runtime_root="/run/user/$(${pkgs.coreutils}/bin/id -u)"
  test "$(< "$ordinary_witness")" = "$runtime_root/orchestrate-nexus/orchestrate.sock"
  test "$(< "$meta_witness")" = "$runtime_root/orchestrate-nexus/orchestrate-meta.sock"

  touch "$out"
''
