{
  config,
  lib,
  ...
}:
let
  theme = import ../../../../lib/nmtui-theme.nix { inherit lib; };
  cfg = config.criomosHome.nmtuiTheme;
  slangColorName = lib.types.enum [
    "black"
    "red"
    "green"
    "brown"
    "blue"
    "magenta"
    "cyan"
    "lightgray"
    "gray"
    "brightred"
    "brightgreen"
    "yellow"
    "brightblue"
    "brightmagenta"
    "brightcyan"
    "white"
  ];
in
{
  options.criomosHome.nmtuiTheme = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Theme libnewt applications, including nmtui, from the terminal's live palette.";
    };

    activeForeground = lib.mkOption {
      type = slangColorName;
      default = "white";
      description = "S-Lang terminal palette name used for active and selected text.";
    };

    activeBackground = lib.mkOption {
      type = slangColorName;
      default = "gray";
      description = "S-Lang terminal palette name used behind active and selected text.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.sessionVariables = {
      NEWT_COLORS = theme.renderNewtColors cfg.activeForeground cfg.activeBackground;
      NMT_NEWT_COLORS = theme.renderNmtNewtColors;
    };
  };
}
