{
  inputs,
  pkgs,
  ...
}:
let
  lib = pkgs.lib // {
    hm.dag.entryAfter = _dependencies: data: { inherit data; };
  };
  colors = {
    base00 = "#000000";
    base01 = "#1a1a1a";
    base02 = "#2d2d2d";
    base03 = "#505050";
    base04 = "#b0b0b0";
    base05 = "#d0d0d0";
    base06 = "#e0e0e0";
    base07 = "#ffffff";
    base08 = "#ff0066";
    base09 = "#ff8800";
    base0A = "#f5c000";
    base0B = "#00cc44";
    base0C = "#cc44ff";
    base0D = "#e040a0";
    base0E = "#bb44ee";
    base0F = "#ff5577";
  };
  moduleResult = import ../../modules/home/profiles/min/chroma.nix {
    inherit inputs lib pkgs;
    config = {
      criomosHome.visualTheme = {
        darkThemeSwitchTiming = "Early";
        lightBase16Scheme = { };
        lightThemeSwitchTiming = "OnTime";
      };
      lib.stylix.colors.withHashtag = colors;
      stylix.base16.mkSchemeAttrs = _scheme: { withHashtag = colors; };
    };
    horizon.node.behavesAs.edge = true;
    textScale.fontPt = 12;
    user.size.min = true;
  };
  moduleContent = if moduleResult ? content then moduleResult.content else moduleResult;
  activation = builtins.unsafeDiscardStringContext moduleContent.home.activation.chromaConfigSeed.data;
  dconfPath = builtins.unsafeDiscardStringContext "${pkgs.dconf}/bin/dconf";
  chromaPackage = inputs.chroma.packages.${pkgs.stdenv.hostPlatform.system}.default;
  pythonWithDbusNext = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.dbus-next ]);
  fakeGamma = pkgs.writeShellApplication {
    name = "chroma-datom-test-gamma";
    runtimeInputs = [ pythonWithDbusNext ];
    text = ''
      exec python ${inputs.chroma}/scripts/chroma-fake-gamma-service.py "$@"
    '';
  };
  daemonSession = pkgs.writeShellApplication {
    name = "chroma-datom-typed-runtime-session";
    runtimeInputs = [
      pkgs.coreutils
      fakeGamma
      chromaPackage
    ];
    text = ''
      set -euo pipefail

      export CHROMA_SANDBOX_FAKE_GAMMA_READY="$XDG_RUNTIME_DIR/gamma-ready"
      chroma-datom-test-gamma &
      gamma_pid=$!
      chroma-daemon &
      chroma_pid=$!
      cleanup() {
        kill "$chroma_pid" "$gamma_pid" >/dev/null 2>&1 || true
        wait "$chroma_pid" >/dev/null 2>&1 || true
        wait "$gamma_pid" >/dev/null 2>&1 || true
      }
      trap cleanup EXIT

      for _ in $(seq 1 200); do
        test -S "$XDG_RUNTIME_DIR/chroma.sock" && break
        if ! kill -0 "$chroma_pid" >/dev/null 2>&1; then
          wait "$chroma_pid"
        fi
        sleep 0.1
      done
      if ! test -S "$XDG_RUNTIME_DIR/chroma.sock"; then
        echo "Chroma daemon did not reach its socket after typed configuration decode" >&2
        exit 1
      fi
      cleanup
      trap - EXIT
    '';
  };
  activationScript = pkgs.writeText "criomos-home-chroma-datom-activation" activation;
  assertions = [
    {
      condition =
        lib.hasInfix "cp \"$next_config\" \"$config_dir/config.datom\"" activation
        && !(lib.hasInfix "cp \"$next_config\" \"$config_dir/config.dotos\"" activation)
        && lib.hasInfix "rm -f \"$config_dir/config.dotos\"" activation;
      message = "Chroma activation must seed config.datom and retire config.dotos.";
    }
    {
      condition = lib.hasInfix "[Terminal Desktop Ghostty Pi]" activation;
      message = "Chroma Datomic concerns must preserve the native concern order and leave Emacs resident.";
    }
    {
      condition = lib.hasInfix "#000000" activation && !(lib.hasInfix "Base00" activation);
      message = "Chroma palettes must use positional Datomic fields.";
    }
    {
      condition = lib.hasInfix "Some.${dconfPath}" activation;
      message = "Chroma Datomic must preserve the Dconf adapter path.";
    }
    {
      condition = lib.hasInfix "Some.{RuntimeRelative.chroma/pi-live-theme.d Some.100 Some.100}" activation;
      message = "Chroma Datomic must preserve Pi runtime registry and timeouts.";
    }
    {
      condition =
        lib.hasInfix "{Sunrise.0 Light}" activation && lib.hasInfix "{Sunset.-30 Dark}" activation;
      message = "Chroma Datomic must preserve OnTime and Early solar schedule offsets.";
    }
    {
      condition =
        lib.hasInfix "{CivilDawn.-30 Cold Minutes.30}" activation
        && lib.hasInfix "{CivilDusk.-60 Warmest Minutes.60}" activation;
      message = "Chroma Datomic must preserve warmth waypoints and ramps.";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "chroma-datom-config-check"
    {
      nativeBuildInputs = [
        pkgs.bash
        pkgs.coreutils
        pkgs.dbus
        daemonSession
      ];
    }
    ''
      export HOME="$TMPDIR/home"
      export XDG_CONFIG_HOME="$HOME/.config"
      export XDG_STATE_HOME="$HOME/.local/state"
      export XDG_CACHE_HOME="$HOME/.cache"
      export XDG_RUNTIME_DIR="$TMPDIR/runtime"
      mkdir -p "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"

      bash ${activationScript}
      test -f "$XDG_CONFIG_HOME/chroma/config.datom"
      test ! -e "$XDG_CONFIG_HOME/chroma/config.dotos"
      dbus-run-session --config-file=${pkgs.dbus}/share/dbus-1/session.conf -- chroma-datom-typed-runtime-session

      printf 'Chroma Datomic configuration was decoded by the current typed runtime\n' > "$out"
    ''
