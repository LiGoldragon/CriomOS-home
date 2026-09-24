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
  legacyConfigToml = ''
    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  legacyConfig = pkgs.writeText "herdr-legacy-config.toml" legacyConfigToml;
  predecessorManagedConfigToml = ''
    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"

    [ui]
    agent_panel_sort = "spaces"
  '';
  predecessorManagedConfig = pkgs.writeText "herdr-predecessor-managed-config.toml" predecessorManagedConfigToml;
  priorHomeManagerFiles = pkgs.runCommand "home-manager-files" { } ''
    mkdir -p "$out/.config/herdr"
    cp ${predecessorManagedConfig} "$out/.config/herdr/config.toml"
  '';
  parsedConfigToml = builtins.fromTOML configToml;
  herdrAdoption = homeConfiguration.config.home.activation.adoptHerdrConfig.data;
  herdrAdoptionScript = pkgs.writeText "herdr-adoption" herdrAdoption;
in
assert parsedConfigToml.ui.toast.delivery == "terminal";
assert parsedConfigToml.theme.auto_switch;
assert parsedConfigToml.theme.dark_name == "catppuccin";
assert parsedConfigToml.theme.light_name == "catppuccin-latte";
assert parsedConfigToml.ui.agent_panel_sort == "spaces";
assert configToml != legacyConfigToml;
pkgs.runCommand "herdr-toast-delivery" {
  nativeBuildInputs = [ pkgs.coreutils ];
} ''
  set -eu

  exact_home="$TMPDIR/exact-home"
  mkdir -p "$exact_home/.config/herdr"
  cp ${legacyConfig} "$exact_home/.config/herdr/config.toml"
  HOME="$exact_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$exact_home/.config/herdr/config.toml"
  cmp ${legacyConfig} \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  sha256sum --check --status \
    "$exact_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager.sha256"

  predecessor_link_home="$TMPDIR/predecessor-link-home"
  mkdir -p "$predecessor_link_home/.config/herdr"
  ln -s ${priorHomeManagerFiles}/.config/herdr/config.toml \
    "$predecessor_link_home/.config/herdr/config.toml"
  HOME="$predecessor_link_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}
  test ! -e "$predecessor_link_home/.config/herdr/config.toml"
  cmp ${legacyConfig} \
    "$predecessor_link_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager"
  sha256sum --check --status \
    "$predecessor_link_home/.local/state/criomos/herdr-adoption/config.toml.pre-home-manager.sha256"

  unrelated_link_home="$TMPDIR/unrelated-link-home"
  mkdir -p "$unrelated_link_home/.config/herdr"
  ln -s ${legacyConfig} "$unrelated_link_home/.config/herdr/config.toml"
  if HOME="$unrelated_link_home" ${pkgs.bash}/bin/bash ${herdrAdoptionScript}; then
    echo "Herdr adoption accepted an unrelated legacy-content symlink" >&2
    exit 1
  fi
  test -L "$unrelated_link_home/.config/herdr/config.toml"

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
