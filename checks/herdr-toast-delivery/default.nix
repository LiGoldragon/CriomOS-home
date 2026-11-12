{ inputs, pkgs, ... }:
let
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = {
        capabilities = [ ];
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
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      inputs.noctalia.homeModules.default
      # The Home deployment supplies criomos.corePackages and the Codex-next
      # client; this standalone fixture imports the same modules so herdr.nix
      # can resolve both Codex executables.
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/codex-next.nix
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
  # The managed config names store paths (the Codex clients); parsing only
  # inspects keys, so the string context is dropped before fromTOML.
  parsedConfigToml = builtins.fromTOML (builtins.unsafeDiscardStringContext configToml);
  checkLinkTargets = homeConfiguration.config.home.activation.checkLinkTargets.data;
  checkLinkTargetsScript = pkgs.writeText "herdr-check-link-targets" checkLinkTargets;
  activationPackage = homeConfiguration.activationPackage;
in
assert parsedConfigToml.ui.toast.delivery == "terminal";
assert parsedConfigToml.theme.auto_switch;
assert parsedConfigToml.theme.dark_name == "catppuccin";
assert parsedConfigToml.theme.light_name == "catppuccin-latte";
assert parsedConfigToml.ui.agent_panel_sort == "spaces";
pkgs.runCommand "herdr-toast-delivery" {
  nativeBuildInputs = [ pkgs.coreutils ];
  inherit activationPackage;
} ''
  set -eu

  # Home Manager creates its declared managed link, and its normal
  # link-target phase accepts that link on a repeated activation.
  managed_repeat_home="$TMPDIR/managed-repeat-home"
  mkdir -p "$managed_repeat_home/.config/herdr"
  ln -s "$activationPackage/home-files/.config/herdr/config.toml" \
    "$managed_repeat_home/.config/herdr/config.toml"
  test "$(readlink -f "$managed_repeat_home/.config/herdr/config.toml")" = \
    ${homeConfiguration.config.xdg.configFile."herdr/config.toml".source}
  HOME="$managed_repeat_home" newGenPath="$activationPackage" \
    ${pkgs.bash}/bin/bash ${checkLinkTargetsScript}
  test -L "$managed_repeat_home/.config/herdr/config.toml"

  touch "$out"
''
