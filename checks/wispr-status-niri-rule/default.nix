{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  profilePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = package: lib.getName package == "wispr-flow";
  };
  runtimeInputs = profilePkgs.callPackage "${inputs.wispr-flow-linux}/nix/runtime-inputs.nix" { };
  wisprFlow = profilePkgs.callPackage "${inputs.wispr-flow-linux}/nix/wispr-flow.nix" {
    inherit runtimeInputs;
    installerExe = inputs.wispr-flow-installer;
  };
  wisprFlowFhs = profilePkgs.callPackage "${inputs.wispr-flow-linux}/nix/fhs.nix" { wispr-flow = wisprFlow; };
  statusCommand = "${wisprFlowFhs}/bin/wispr-flow-status";
  statusCommandText = builtins.unsafeDiscardStringContext statusCommand;
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = profilePkgs;
    extraSpecialArgs = {
      inherit inputs;
      constants = inputs.criomos-lib.lib.constants;
      horizon.node.behavesAs.edge = true;
      user = { useFastRepeat = false; size.medium = true; };
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      ../../modules/home/profiles/min/niri.nix
      {
        home = { username = "niri-status-check"; homeDirectory = "/home/niri-status-check"; stateVersion = "26.05"; };
        programs.niri.package = profilePkgs.niri;
        stylix = { enable = true; polarity = "dark"; base16Scheme = ../../modules/home/ignis.yaml; };
      }
    ];
  };
  settings = homeConfiguration.config.programs.niri.settings;
  generatedConfig = homeConfiguration.config.programs.niri.finalConfig;
in
assert lib.assertMsg (settings.binds."Mod+X".repeat == false) "Wispr hands-free must be a one-shot binding";
assert lib.assertMsg (
  !builtins.any (rule: builtins.any (match: (match.app-id or "") == "^wispr-flow$") rule.matches) settings.window-rules
) "Niri must not retain a Wispr Status window workaround";
assert lib.assertMsg (
  lib.hasInfix ''Mod+X repeat=false { spawn "${statusCommandText}" "toggle-hands-free"; }'' generatedConfig
) "the rendered Mod+X binding must invoke the provider's packaged control CLI exactly";
pkgs.runCommand "wispr-status-niri-rule" { nativeBuildInputs = [ pkgs.niri ]; } ''
  ${pkgs.niri}/bin/niri validate -c ${homeConfiguration.config.xdg.configFile.niri-config.source}
  touch "$out"
''
