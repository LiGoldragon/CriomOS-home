{
  inputs,
  pkgs,
  homePkgs ? inputs.pkgs.pkgs.extend (pkgs.lib.composeManyExtensions (import ../../overlays { inherit inputs; })),
  ...
}:
let
  lib = homePkgs.lib;
  ytDlp = homePkgs.yt-dlp;
  previousVersion = "2026.07.04";
  sourceVersion = builtins.head (
    builtins.match ".*__version__ = '([^']+)'.*" (
      builtins.readFile "${inputs.yt-dlp}/yt_dlp/version.py"
    )
  );
  profileAggregate = import ../../modules/home/default.nix {
    flake = null;
    inputs = null;
  };
  profileImports =
    (profileAggregate {
      config = { };
      inherit lib;
    }).imports;
  minProfile = ../../modules/home/profiles/min;
  mediumProfile = ../../modules/home/profiles/med;
  minModule = import minProfile {
    inherit lib;
    pkgs = homePkgs;
    criomos-lib = null;
    user = {
      useColemak = false;
      hasPubKey = false;
      gitSigningKey = null;
      matrixId = null;
      size = {
        min = true;
        medium = true;
        large = false;
        max = false;
      };
      isMultimediaDev = false;
      emailAddress = "yt-dlp-check@example.invalid";
      githubId = "yt-dlp-check";
      name = "yt-dlp check";
    };
    horizon.node.machine.architecture = "x86_64";
    config = { };
    inputs = { };
    hexis = null;
    rustToolchain = null;
  };
  mediumModule = import mediumProfile {
    inherit lib;
    pkgs = homePkgs;
    user = {
      githubId = "yt-dlp-check";
      useColemak = false;
      size.medium = true;
    };
  };
  moduleContent = module:
    if module ? config && module.config ? content then
      module.config.content
    else if module ? content then
      module.content
    else
      module;
  minPackages = (moduleContent minModule).home.packages;
  mediumPackages = (moduleContent mediumModule).home.packages;
  importsProfile = profile: builtins.any (module: toString module == toString profile) profileImports;
in
assert ytDlp.src == inputs.yt-dlp;
assert ytDlp.version == sourceVersion;
assert lib.versionAtLeast sourceVersion previousVersion;
assert importsProfile minProfile;
assert importsProfile mediumProfile;
assert builtins.elem homePkgs.mpv minPackages;
assert builtins.elem ytDlp mediumPackages;
homePkgs.runCommand "yt-dlp-current-source"
  {
    inherit ytDlp;
  }
  ''
    test -x "$ytDlp/bin/yt-dlp"
    test "$("$ytDlp/bin/yt-dlp" --version)" = "${sourceVersion}"
    touch "$out"
  ''
