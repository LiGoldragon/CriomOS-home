{ pkgs, inputs, ... }:
let
  emacsBase = pkgs.emacs-pgtk;
  emacsPackageSet = pkgs.emacsPackagesFor emacsBase;
  chromaTheme = inputs.chroma-emacs.lib.mkChromaTheme { inherit emacsPackageSet; };
  emacs = emacsPackageSet.withPackages (_: [ chromaTheme ]);
  dark = {
    base00 = "#000000"; base01 = "#1a1a1a"; base02 = "#2d2d2d"; base03 = "#505050";
    base04 = "#b0b0b0"; base05 = "#d0d0d0"; base06 = "#e0e0e0"; base07 = "#ffffff";
    base08 = "#ff0066"; base09 = "#ff8800"; base0A = "#f5c000"; base0B = "#00cc44";
    base0C = "#cc44ff"; base0D = "#e040a0"; base0E = "#bb44ee"; base0F = "#ff5577";
  };
  light = {
    base00 = "#faf5f0"; base01 = "#efe8e2"; base02 = "#ddd5ce"; base03 = "#887a70";
    base04 = "#6a5e55"; base05 = "#3d3530"; base06 = "#2a2420"; base07 = "#1a1510";
    base08 = "#cc0044"; base09 = "#d06600"; base0A = "#b89000"; base0B = "#1a8a30";
    base0C = "#9930cc"; base0D = "#b03080"; base0E = "#8822bb"; base0F = "#cc3355";
  };
  ignisThemeDir = import ../../modules/home/emacs/ignis-themes.nix { inherit pkgs dark light; };
  homeThemeInit = pkgs.writeText "criomos-home-chroma-theme-init.el" (
    builtins.readFile ../../modules/home/emacs/chroma-theme-init.el
  );
  moduleContent = module:
    if module ? config && module.config ? content then module.config.content
    else if module ? content then module.content
    else module;
  homeEmacsModule = import ../../modules/home/profiles/med/emacs.nix {
    inherit pkgs inputs;
    lib = pkgs.lib;
    textScale.emacsHeight = 14;
    user = {
      size.medium = true;
      preferredEditor = "Codium";
    };
  };
  homeEmacs = moduleContent homeEmacsModule;
  homeEmacsPackage = homeEmacs.programs.emacs.package;
  homeEmacsServicePackage = homeEmacs.services.emacs.package;
  homeInitCompiled = builtins.dirOf (toString homeEmacs.home.file.".emacs.d/init.el".source);
  pythonWithDbusNext = pkgs.python3.withPackages (pythonPackages: [ pythonPackages.dbus-next ]);
  fakeGamma = pkgs.writeShellApplication {
    name = "chroma-emacs-test-gamma";
    runtimeInputs = [ pythonWithDbusNext ];
    text = ''
      exec python ${inputs.chroma}/scripts/chroma-fake-gamma-service.py "$@"
    '';
  };
  witness = pkgs.writeShellApplication {
    name = "chroma-emacs-resident-witness";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.dbus
      pkgs.glib
      pkgs.gnugrep
      pkgs.inotify-tools
      emacs
      fakeGamma
      inputs.chroma.packages.${pkgs.stdenv.hostPlatform.system}.default
    ];
    text = builtins.readFile ./run.sh;
  };
in
assert homeEmacsPackage == homeEmacsServicePackage;
pkgs.runCommand "chroma-emacs-resident-check"
  {
    nativeBuildInputs = [ witness homeInitCompiled ];
    CHROMA_EMACS_TEST_THEME_INIT = homeThemeInit;
    CHROMA_EMACS_TEST_THEME_DIRECTORY = ignisThemeDir;
    CHROMA_EMACS_HOME_INIT_COMPILED = homeInitCompiled;
    CHROMA_EMACS_HOME_PACKAGE = homeEmacsPackage;
    CHROMA_EMACS_DBUS_SESSION_CONF = "${pkgs.dbus}/share/dbus-1/session.conf";
  }
  ''
    chroma-emacs-resident-witness
    touch "$out"
  ''
