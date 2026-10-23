{
  pkgs,
  inputs,
  releases ? {
    stable = {
      generation = "938ec35";
      runtime = inputs.flow.packages.${pkgs.stdenv.hostPlatform.system}.default;
      runtimeDirectory = "flow";
    };
    last = null;
    next = null;
  },
  selected ? "stable",
  ...
}:
let
  lib = pkgs.lib;
  available = lib.filterAttrs (_: release: release != null) releases;
  selectedRelease =
    if builtins.hasAttr selected available then
      available.${selected}
    else
      throw "Flow release ${selected} is unavailable";
  writeRelease = channel: release: ''
    cat > "$out/bin/flow-${channel}" <<'SH'
    #!${pkgs.runtimeShell}
    export FLOW_SOCKET="''${XDG_RUNTIME_DIR:?}/${release.runtimeDirectory}/flow.sock"
    exec ${release.runtime}/bin/flow "$@"
    SH
    cat > "$out/bin/flow-meta-${channel}" <<'SH'
    #!${pkgs.runtimeShell}
    export FLOW_META_SOCKET="''${XDG_RUNTIME_DIR:?}/${release.runtimeDirectory}/flow-meta.sock"
    exec ${release.runtime}/bin/flow-meta "$@"
    SH
    cat > "$out/bin/flow-nexus-${channel}" <<'SH'
    #!${pkgs.runtimeShell}
    exec ${release.runtime}/bin/flow-nexus "$@"
    SH
    cat > "$out/bin/flow-hook-${channel}" <<'SH'
    #!${pkgs.runtimeShell}
    export FLOW_SOCKET="''${XDG_RUNTIME_DIR:?}/${release.runtimeDirectory}/flow.sock"
    exec ${release.runtime}/bin/flow-hook "$@"
    SH
    chmod +x "$out/bin/"*"-${channel}"
  '';
in
pkgs.runCommand "flow-release-set-${selectedRelease.generation}"
  {
    passthru = {
      inherit available selected selectedRelease;
    };
  }
  ''
    mkdir -p "$out/bin"
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList writeRelease available)}
    for name in flow flow-meta flow-nexus flow-hook; do
      ln -s "$out/bin/$name-${selected}" "$out/bin/$name"
    done
  ''
