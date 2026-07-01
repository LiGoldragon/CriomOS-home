{
  lib,
  pkgs,
  user,
  inputs,
  ...
}:
let
  inherit (user) size;
  system = pkgs.stdenv.hostPlatform.system;

  # `annas` — Anna's Archive book/article search + download CLI.
  # Upstream binary is `annas-mcp`; we ship it as `annas` so the
  # name matches the verb. The wrapper injects three env vars per
  # invocation (see lore/annas/basic-usage.md):
  #   ANNAS_SECRET_KEY      — pulled from gopass at annas-archive.gl/secret-key
  #   ANNAS_DOWNLOAD_PATH   — defaults to $PWD so files land where you ran the cmd
  #   ANNAS_BASE_URL        — defaults to annas-archive.gd
  # Any of the three may be overridden by exporting before the call.
  annas-mcp-bin = pkgs.buildGoModule {
    pname = "annas-mcp";
    version = "0.0.5";
    src = inputs.annas-mcp;
    vendorHash = "sha256-2NdG5p2XfrhVgi388dRDBUSGwg6ybnzfn9495TWNGsA=";
    subPackages = [ "cmd/annas-mcp" ];
    doCheck = false;
    meta = {
      description = "Anna's Archive book/article CLI";
      homepage = "https://github.com/iosifache/annas-mcp";
      license = lib.licenses.mit;
      mainProgram = "annas-mcp";
    };
  };

  annas = pkgs.writeShellApplication {
    name = "annas";
    runtimeInputs = [ annas-mcp-bin pkgs.gopass ];
    text = ''
      : "''${ANNAS_SECRET_KEY:=$(gopass show -o annas-archive.gl/secret-key 2>/dev/null || true)}"
      : "''${ANNAS_DOWNLOAD_PATH:=$PWD}"
      : "''${ANNAS_BASE_URL:=annas-archive.gd}"
      export ANNAS_SECRET_KEY ANNAS_DOWNLOAD_PATH ANNAS_BASE_URL
      exec annas-mcp "$@"
    '';
  };
in
lib.mkIf size.medium {
  home.packages = [
    inputs.substack-cli.packages.${system}.default
    inputs.claude-answers.packages.${system}.default
    annas

    # bd work-tracking runtime: bd drives beads, dolt persists them,
    # and tmux/flock/lsof/pgrep are the process tools bd shells out to.
    pkgs.beads
    pkgs.dolt
    pkgs.tmux
    pkgs.lsof
    pkgs.procps      # pgrep
    pkgs.util-linux  # flock
  ];
}
