{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  profilePkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = _: true;
  };
  homeConfiguration = inputs.home-manager.lib.homeManagerConfiguration {
    pkgs = profilePkgs;
    extraSpecialArgs = {
      inherit inputs;
      constants = inputs.criomos-lib.lib.constants;
      horizon.node.behavesAs.edge = true;
      user = {
        useFastRepeat = false;
        size = "Medium";
      };
    };
    modules = [
      inputs.stylix.homeModules.stylix
      inputs.niri-flake.homeModules.config
      ../../modules/home/profiles/min/niri.nix
      {
        home = {
          username = "chatgpt-voice-check";
          homeDirectory = "/home/chatgpt-voice-check";
          stateVersion = "26.05";
        };
        programs.niri.package = profilePkgs.niri;
        stylix = {
          enable = true;
          polarity = "dark";
          base16Scheme = ../../modules/home/ignis.yaml;
        };
      }
    ];
  };
  settings = homeConfiguration.config.programs.niri.settings;
  chatgptRule = lib.findFirst (
    rule: builtins.any (match: (match.app-id or "") == "^chatgpt$") rule.matches
  ) null settings.window-rules;
  microphoneMuteBinding = settings.binds."XF86AudioMicMute".action.spawn;
in
assert lib.assertMsg (chatgptRule != null)
  "ChatGPT must have a Niri window rule";
assert lib.assertMsg (!chatgptRule.open-floating)
  "ChatGPT's voice surface must open in Niri's normal layout";
assert lib.assertMsg (builtins.length microphoneMuteBinding == 1)
  "The microphone mute binding must invoke one declarative helper";
pkgs.runCommand "chatgpt-voice-niri-rule" { nativeBuildInputs = [ pkgs.niri ]; } ''
  ${pkgs.niri}/bin/niri validate -c ${homeConfiguration.config.xdg.configFile.niri-config.source}
  touch "$out"
''
