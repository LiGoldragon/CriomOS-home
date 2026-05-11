{ lib, ... }:
let
  schemeType =
    with lib.types;
    oneOf [
      path
      lines
      attrs
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
  };
}
