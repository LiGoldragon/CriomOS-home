{
  lib,
  runCommand,
  python3,
}:
let
  evaluated = lib.evalModules {
    modules = [
      ../../modules/home/profiles/min/nmtui-theme.nix
      {
        options.home.sessionVariables = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
        };
      }
    ];
  };
  sessionVariables = evaluated.config.home.sessionVariables;
in
runCommand "nmtui-theme"
  {
    nativeBuildInputs = [ python3 ];
    inherit (sessionVariables) NEWT_COLORS NMT_NEWT_COLORS;
    passAsFile = [
      "NEWT_COLORS"
      "NMT_NEWT_COLORS"
    ];
  }
  ''
    python ${./verify.py} "$NEWT_COLORSPath" "$NMT_NEWT_COLORSPath"
    touch "$out"
  ''
