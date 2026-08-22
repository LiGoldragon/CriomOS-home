{ pkgs, inputs, ... }:
let
  emacsBase = pkgs.emacs-pgtk;
  emacsPackageSet = pkgs.emacsPackagesFor emacsBase;
  chromaTheme = inputs.chroma-emacs.lib.mkChromaTheme { inherit emacsPackageSet; };
  emacs = emacsPackageSet.withPackages (_: [ chromaTheme ]);
  homeThemeInit = pkgs.writeText "criomos-home-chroma-theme-init.el" (
    builtins.readFile ../../modules/home/emacs/chroma-theme-init.el
  );
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
pkgs.runCommand "chroma-emacs-resident-check"
  {
    nativeBuildInputs = [ witness ];
    CHROMA_EMACS_TEST_THEME_INIT = homeThemeInit;
    CHROMA_EMACS_DBUS_SESSION_CONF = "${pkgs.dbus}/share/dbus-1/session.conf";
  }
  ''
    chroma-emacs-resident-witness
    touch "$out"
  ''
