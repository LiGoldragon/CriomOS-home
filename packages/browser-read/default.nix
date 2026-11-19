{ pkgs, inputs, playwrightChrome, registryRelativePath ? "browser-read/registry.datom", ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  base = inputs.flow-0550.inputs.base;
  workspace = base.lib.workspace.${system} { cargoNix = ./frontend/Cargo.nix; };
  runtime = workspace.binaries "browser-read" [ ];
  command = pkgs.writeShellScriptBin "browser-read" ''
    exec ${runtime}/bin/browser-read \
      ${pkgs.python3}/bin/python3 ${./session.py} \
      ${playwrightChrome}/bin/playwright-chrome \
      "''${XDG_CONFIG_HOME:-$HOME/.config}/${registryRelativePath}" "$@"
  '';
in
command.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    inherit runtime;
    rustChecks = (base.lib.workspaceOutputs { cargoNix = ./frontend/Cargo.nix; }).checks.${system}.default;
  };
})
