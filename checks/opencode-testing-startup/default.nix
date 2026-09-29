{ pkgs, ... }:
let
  inherit (pkgs) lib;
  module = ../../modules/home/profiles/min/opencode.nix;
  enabled = lib.evalModules {
    modules = [
      {
        options = {
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [ ];
          };
          home.packages = lib.mkOption {
            type = lib.types.listOf lib.types.package;
            default = [ ];
          };
          systemd.user.services = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = { };
          };
        };
      }
      module
    ];
    specialArgs = {
      inherit pkgs;
      horizon.node = {
      capabilities = [ { kind = "openCodeTesting"; } ];
      keys.yggdrasil.address = "200:abcd::1";
      };
    };
  };
  service = enabled.config.systemd.user.services.opencode-testing.Service;
in
assert service.RuntimeDirectory == "opencode-testing/scratch";
assert service.WorkingDirectory == "%t/opencode-testing/scratch";
assert !(service ? ExecStartPre);
pkgs.runCommand "opencode-testing-startup" { } ''
  runtime="$TMPDIR/runtime/opencode-testing"
  scratch="$runtime/scratch"
  mkdir -p "$runtime"

  # The old unit tried to enter scratch before its pre-start mkdir could run.
  test ! -d "$scratch"
  if (cd "$scratch" && mkdir -p "$scratch"); then
    echo "old unit unexpectedly entered its missing working directory" >&2
    exit 1
  fi

  # RuntimeDirectory creates the declared scratch directory before ExecStart.
  mkdir -p "$scratch"
  (cd "$scratch" && test -d .)
  mkdir -p "$out"
''
