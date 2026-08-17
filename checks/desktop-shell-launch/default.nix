{ pkgs, inputs, ... }:
let
  niri = builtins.readFile ../../modules/home/profiles/min/niri.nix;
  sfwbar = builtins.readFile ../../modules/home/profiles/min/sfwbar.nix;
  uiPriority = builtins.readFile ../../modules/home/profiles/min/ui-priority.nix;
  noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  noctaliaExecutable = pkgs.lib.getExe' noctalia "noctalia";
in
assert pkgs.lib.hasInfix
  "noctaliaShell = inputs.noctalia.packages.\${pkgs.stdenv.hostPlatform.system}.default;"
  niri;
assert pkgs.lib.hasInfix ''noctaliaExecutable = lib.getExe' noctaliaShell "noctalia";'' niri;
assert pkgs.lib.hasInfix "{ command = [ noctaliaExecutable ]; }" niri;
assert pkgs.lib.hasInfix ''exec ''${noctaliaExecutable} msg "$@"'' niri;
assert !(pkgs.lib.hasInfix "noctalia-shell" niri);
assert pkgs.lib.hasInfix ''"Mod+D".action = a.spawn "''${noctaliaIpc}" "panel-toggle" "launcher";''
  niri;
assert pkgs.lib.hasInfix
  ''"Mod+Space".action = a.spawn "''${noctaliaIpc}" "panel-toggle" "launcher";''
  niri;
assert pkgs.lib.hasInfix "\${noctaliaIpc} session lock" niri;
assert !(pkgs.lib.hasInfix "quickshell" niri);
assert pkgs.lib.hasInfix "(^|/| )noctalia( |$)" uiPriority;
assert !(pkgs.lib.hasInfix "quickshell" uiPriority);
assert pkgs.lib.hasInfix ''mode = "auto";'' sfwbar;
assert pkgs.lib.hasInfix ''source = "wallpaper";'' sfwbar;
assert pkgs.lib.hasInfix ''wallpaper_scheme = "m3-rainbow";'' sfwbar;
assert pkgs.lib.hasInfix "margin_ends = 0;" sfwbar;
pkgs.runCommand "desktop-shell-launch"
  {
    nativeBuildInputs = [
      noctalia
      pkgs.gnugrep
    ];
  }
  ''
    test -x ${noctaliaExecutable}
    ${noctaliaExecutable} msg --help | grep -F 'panel-toggle'
    ${noctaliaExecutable} msg session --help | grep -F 'one of: lock'
    touch "$out"
  ''
