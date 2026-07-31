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
  emacsclientPath = builtins.unsafeDiscardStringContext "${pkgs.emacs-pgtk}/bin/emacsclient";
  assertions = [
    {
      condition = lib.hasInfix "(Base00 #000000)" activation;
      message = "Chroma palette atoms must be bare DOTOS strings";
    }
    {
      condition = !(lib.hasInfix "(Base00 \"#000000\")" activation);
      message = "Chroma palette atoms must not be quoted";
    }
    {
      condition = lib.hasInfix "(Dconf ${dconfPath})" activation;
      message = "Chroma dconf path must be a bare DOTOS atom";
    }
    {
      condition = !(lib.hasInfix "(Dconf \"" activation);
      message = "Chroma dconf path must not be quoted";
    }
    {
      condition = lib.hasInfix "(Emacsclient ${emacsclientPath})" activation;
      message = "Chroma emacsclient path must be a bare DOTOS atom";
    }
    {
      condition = !(lib.hasInfix "(Emacsclient \"" activation);
      message = "Chroma emacsclient path must not be quoted";
    }
    {
      condition = !(lib.hasInfix "(Dark \"" activation);
      message = "Chroma Ghostty dark template path must not be quoted";
    }
    {
      condition = !(lib.hasInfix "(Light \"" activation);
      message = "Chroma Ghostty light template path must not be quoted";
    }
    {
      condition = lib.hasInfix "(Concerns Terminal Desktop Ghostty Emacs Pi)" activation;
      message = "Chroma config must enable the Pi live theme concern";
    }
    {
      condition = lib.hasInfix "(RegistryDirectory (RuntimeRelative chroma/pi-live-theme.d))" activation;
      message = "Chroma Pi theme control must use the runtime registry directory";
    }
    {
      condition = !(lib.hasInfix "current-mode" activation);
      message = "Chroma config must not restore the old current-mode sidecar";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "chroma-dotos-config-check" { } ''
    printf 'chroma DOTOS config syntax checked\n' > "$out"
  ''
