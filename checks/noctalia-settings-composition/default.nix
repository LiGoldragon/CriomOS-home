{ pkgs, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  hexisPackage = inputs.hexis.packages.${system}.default;
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hexis = hexisPackage;
      horizon.node.behavesAs.edge = true;
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.noctalia.homeModules.default
      ../../modules/home/profiles/min/sfwbar.nix
      {
        home = {
          username = "noctalia-check";
          homeDirectory = "/home/noctalia-check";
          stateVersion = "26.11";
        };

        # Exercise the actual upstream dark-mode definition that caused the
        # activation build conflict, rather than a hand-written approximation.
        stylix = {
          enable = true;
          polarity = "dark";
          base16Scheme = ../../modules/home/ignis.yaml;
        };

        programs.noctalia.validateConfig = false;
      }
    ];
  };
  settings = homeConfiguration.config.programs.noctalia.settings;
  configToml =
    builtins.readFile
      homeConfiguration.config.xdg.configFile."noctalia/config.toml".source;
  parsedConfigToml = builtins.fromTOML configToml;
  noctaliaShell = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaExecutable = pkgs.lib.getExe' noctaliaShell "noctalia";
  generatedConfig = pkgs.writeText "noctalia-settings-composition.toml" configToml;
  activation = homeConfiguration.config.home.activation;
  reconcileNoctaliaSettings =
    if activation ? reconcileNoctaliaSettings then
      activation.reconcileNoctaliaSettings.data
    else
      activation.reconcileNoctaliaThemeMode.data;
  reconcileNoctaliaSettingsScript = pkgs.writeShellScript "reconcile-noctalia-settings" reconcileNoctaliaSettings;
in
assert pkgs.lib.assertMsg (
  settings.theme.mode == "external"
) "Noctalia must consume Chroma's external light/dark mode";
assert pkgs.lib.assertMsg (
  settings.theme.source == "wallpaper"
) "the declared Noctalia theme source must override Stylix's custom-palette target";
assert pkgs.lib.assertMsg (
  settings.theme.wallpaper_scheme == "m3-rainbow"
) "the declared Noctalia wallpaper scheme must remain effective";
assert pkgs.lib.assertMsg (
  settings.bar.main.margin_ends == 0
) "the Noctalia bar must remain configured for full output width";
assert pkgs.lib.assertMsg (
  settings.bar.main.start == [
    "launcher"
    "clock"
    "media"
  ]
  && settings.bar.main.center == [ "workspaces" ]
  &&
    settings.bar.main.end == [
      "wispr-status-widget"
      "listener-level"
      "tray"
      "battery"
      "volume"
      "brightness"
      "control-center"
    ]
  && settings.widget.wispr-status-widget.type == "criomos/wispr-status:wispr-status-widget"
  && settings.widget.listener-level.type == "criomos/listener-level:level"
  && settings.widget.tray.drawer
  && settings.widget.battery.display_mode == "graphic"
) "the Noctalia bar must retain its complete v5 lane order and listener plugin alias";
assert pkgs.lib.assertMsg (
  !(settings.bar ? widgets)
  && !(settings.bar.main ? left)
  && !(settings.bar.main ? right)
  && !(settings.bar.main ? startWidgets)
  && !(settings.bar.main ? endWidgets)
) "the Noctalia bar must not retain v4 lane fields";
assert pkgs.lib.assertMsg (builtins.all builtins.isString (
  settings.bar.main.start ++ settings.bar.main.center ++ settings.bar.main.end
)) "every Noctalia v5 bar lane entry must be a string";
assert pkgs.lib.assertMsg (
  !(builtins.elem "solar-time" settings.bar.main.start)
  && !(builtins.elem "active-network" settings.bar.main.end)
  && !(builtins.elem "plugin:solar-time" settings.bar.main.start)
  && !(builtins.elem "plugin:active-network" settings.bar.main.end)
) "unregistered v4 plugin entries must not remain in v5 bar lanes";
assert pkgs.lib.assertMsg (
  parsedConfigToml.idle.pre_action_fade_seconds == 5
  &&
    parsedConfigToml.idle.behavior."screen-off" == {
      enabled = true;
      timeout = 300;
      action = "screen_off";
    }
  &&
    parsedConfigToml.idle.behavior.lock == {
      enabled = true;
      timeout = 3600;
      action = "lock";
    }
) "the generated Noctalia TOML must declare the v5 screen-off and lock behaviors";
assert pkgs.lib.assertMsg (
  !(parsedConfigToml.idle ? enabled)
  && !(parsedConfigToml.idle ? fadeDuration)
  && !(parsedConfigToml.idle ? lockTimeout)
  && !(parsedConfigToml.idle ? screenOffTimeout)
  && !(parsedConfigToml.idle ? suspendTimeout)
) "the generated Noctalia TOML must not retain ignored v4 idle settings";
pkgs.runCommand "noctalia-settings-composition" { nativeBuildInputs = [ noctaliaShell ]; } ''
    state_home="$TMPDIR/noctalia-state-home"
    state_file="$state_home/.local/state/noctalia/settings.toml"
    mkdir -p "$(dirname "$state_file")"
    cat >"$state_file" <<'EOF'
  [theme]
  mode = "auto"

  [plugins]
  enabled = ["criomos/listener-level"]

  [preserved]
  value = "user-state"
  EOF

    export HOME="$state_home"
    export DRY_RUN_CMD=
    export VERBOSE_ARG=
    ${reconcileNoctaliaSettingsScript}

    ${pkgs.python3}/bin/python - "$state_file" <<'PY'
  import pathlib
  import sys
  import tomllib

  settings = tomllib.loads(pathlib.Path(sys.argv[1]).read_text())
  assert settings["theme"]["mode"] == "external"
  assert settings["plugins"]["enabled"] == [
      "criomos/wispr-status",
      "criomos/listener-level",
  ]
  assert settings["preserved"]["value"] == "user-state"
  PY

    validation_output="$TMPDIR/noctalia-config-validation"
    ${noctaliaExecutable} config validate ${generatedConfig} >"$validation_output" 2>&1
    ${pkgs.coreutils}/bin/cat "$validation_output"
    if ${pkgs.gnugrep}/bin/grep -E ':[[:space:]](idle\.|bar\.(widgets|main)\.|widget\.)[^:]*:[[:space:]]unknown setting' "$validation_output"; then
      echo 'Noctalia validator reported an obsolete setting' >&2
      exit 1
    fi
    touch "$out"
''
