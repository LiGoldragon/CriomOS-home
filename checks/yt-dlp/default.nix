{ inputs, pkgs, ... }:
let
  lib = pkgs.lib;
  system = pkgs.stdenv.hostPlatform.system;
  packageOverlays = import ../../overlays { inherit inputs; };
  profilePkgs =
    (import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
    }).extend
      (lib.composeManyExtensions packageOverlays);
  ytDlp = profilePkgs.yt-dlp;
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
    pkgs = profilePkgs;
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
    horizon.node.machine.arch = "x86-64";
    config = { };
    inputs = { };
    hexis = null;
    rustToolchain = null;
  };
  mediumModule = import mediumProfile {
    inherit lib;
    pkgs = profilePkgs;
    user = {
      githubId = "yt-dlp-check";
      useColemak = false;
      size.medium = true;
    };
  };
  minPackages = (minModule.content or minModule).home.packages;
  mediumPackages = (mediumModule.content or mediumModule).home.packages;
  importsProfile = profile: builtins.any (module: toString module == toString profile) profileImports;
in
assert ytDlp.src == inputs.yt-dlp;
assert ytDlp.version == sourceVersion;
assert lib.versionAtLeast sourceVersion previousVersion;
assert importsProfile minProfile;
assert importsProfile mediumProfile;
assert builtins.elem profilePkgs.mpv minPackages;
assert builtins.elem ytDlp mediumPackages;
profilePkgs.runCommand "yt-dlp-current-source"
  {
    inherit ytDlp;
  }
  ''
    test -x "$ytDlp/bin/yt-dlp"
    test "$("$ytDlp/bin/yt-dlp" --version)" = "${sourceVersion}"
    touch "$out"
  ''
