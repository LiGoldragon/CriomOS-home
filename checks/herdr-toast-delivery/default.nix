{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        size = "Min";
        useColemak = false;
        hasPublicKey = false;
        gitSigningKey = "";
        matrixId = "";
        isMultimediaDev = false;
        emailAddress = "herdr-toast-check@example.invalid";
        githubId = "herdr-toast-check";
        name = "herdr-toast-check";
        publicKeys = [ ];
      };
      horizon.node = {
        name = "herdr-toast-check";
        machine.architecture = "x86_64";
      };
      hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [
      ../../modules/home/profiles/min/default.nix
      {
        home = {
          username = "herdr-toast-check";
          homeDirectory = "/home/herdr-toast-check";
          stateVersion = "26.11";
        };
      }
    ];
  };
  configToml = builtins.readFile homeConfiguration.config.xdg.configFile."herdr/config.toml".source;
  parsedConfigToml = builtins.fromTOML configToml;
  herdrAdoption = homeConfiguration.config.home.activation.adoptHerdrConfig.data;
  herdrAdoptionScript = pkgs.writeText "herdr-adoption" herdrAdoption;
in
assert parsedConfigToml.ui.toast.delivery == "terminal";
assert parsedConfigToml.theme.auto_switch;
assert parsedConfigToml.theme.dark_name == "catppuccin";
assert parsedConfigToml.theme.light_name == "catppuccin-latte";
assert parsedConfigToml.ui.agent_panel_sort == "spaces";
pkgs.runCommand "herdr-toast-delivery" {
  nativeBuildInputs = [ pkgs.coreutils ];
} ''
  set -eu

  exact_home="$TMPDIR/exact-home"
  mkdir -p "$exact_home/.config/herdr"
  cp ${homeConfiguration.config.xdg.configFile."herdr/config.toml".source} "$exact_home/.config/herdr/config.toml"
  HOME="$exact_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$exact_home/.config/herdr/config.toml"
  cmp ${homeConfiguration.config.xdg.configFile."herdr/config.toml".source} \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  sha256sum --check --status \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager.sha256"

  mismatch_home="$TMPDIR/mismatch-home"
  mkdir -p "$mismatch_home/.config/herdr"
  printf '%s\n' '[ui.toast]' 'delivery = "desktop"' > "$mismatch_home/.config/herdr/config.toml"
  if HOME="$mismatch_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted a mismatched configuration" >&2
    exit 1
  fi
  printf '%s\n' '[ui.toast]' 'delivery = "desktop"' > "$TMPDIR/mismatched-config.toml"
  cmp "$TMPDIR/mismatched-config.toml" "$mismatch_home/.config/herdr/config.toml"

  missing_home="$TMPDIR/missing-home"
  mkdir -p "$missing_home/.config/herdr"
  if HOME="$missing_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted a missing configuration" >&2
    exit 1
  fi

  touch "$out"
''
