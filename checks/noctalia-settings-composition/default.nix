{ pkgs, inputs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      hexis = pkgs.writeShellScriptBin "hexis" "exit 0";
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
in
assert pkgs.lib.assertMsg (
  settings.theme.mode == "auto"
) "the declared Noctalia theme mode must override Stylix's dark-mode target";
assert pkgs.lib.assertMsg (
  settings.theme.source == "wallpaper"
) "the declared Noctalia theme source must override Stylix's custom-palette target";
assert pkgs.lib.assertMsg (
  settings.theme.wallpaper_scheme == "m3-rainbow"
) "the declared Noctalia wallpaper scheme must remain effective";
assert pkgs.lib.assertMsg (
  settings.bar.widgets.margin_ends == 0
) "the Noctalia bar must remain configured for full output width";
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
  validation_output="$TMPDIR/noctalia-config-validation"
  ${noctaliaExecutable} config validate ${generatedConfig} >"$validation_output" 2>&1
  ${pkgs.coreutils}/bin/cat "$validation_output"
  if ${pkgs.gnugrep}/bin/grep -E ':[[:space:]]idle\.[^:]*:[[:space:]]unknown setting' "$validation_output"; then
    echo 'Noctalia validator reported an unknown idle setting' >&2
    exit 1
  fi
  touch "$out"
''
