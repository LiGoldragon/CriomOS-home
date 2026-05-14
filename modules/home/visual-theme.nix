{ lib, ... }:
let
  schemeType =
    with lib.types;
    oneOf [
      path
      lines
      attrs
    ];
  themeSwitchTimingType = lib.types.enum [
    "ExtremelyEarly"
    "VeryEarly"
    "Early"
    "OnTime"
    "Late"
    "VeryLate"
    "ExtremelyLate"
  ];
in
{
  options.criomosHome.visualTheme = {
    darkBase16Scheme = lib.mkOption {
      type = schemeType;
      default = ./ignis.yaml;
      description = "Base16 scheme Stylix uses for the dark visual theme.";
    };

    lightBase16Scheme = lib.mkOption {
      type = schemeType;
      default = ./ignis-light.yaml;
      description = "Base16 scheme Stylix uses for the light visual theme.";
    };

    lightThemeSwitchTiming = lib.mkOption {
      type = themeSwitchTimingType;
      default = "OnTime";
      description = "When Chroma switches to the light theme, relative to geolocated sunrise.";
    };

    darkThemeSwitchTiming = lib.mkOption {
      type = themeSwitchTimingType;
      default = "Early";
      description = "When Chroma switches to the dark theme, relative to geolocated sunset.";
    };
  };
}
