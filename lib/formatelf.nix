{ pkgs }:

let
  inherit (pkgs)
    lib
    stdenv
    rustPlatform
    fetchFromGitHub
    makeSetupHook
    ;
  version = "0-unstable-2026-08-11";
  src = fetchFromGitHub {
    owner = "Mic92";
    repo = "formatelf";
    rev = "2b36d819b48c0bfd4a084e6f0ce430633d8ee5f4";
    hash = "sha256-wWCpCxVogWKo/ivGfmAmD8YE8H4CQfs52lMdKsELK/w=";
  };
  formatelf = rustPlatform.buildRustPackage {
    pname = "formatelf";
    inherit version src;
    cargoHash = "sha256-+chzNYelw+fcWhIMSbJgVyOD48vV/Z6Cg5nhbfs16Xs=";
    doCheck = false;
    postInstall = ''
      ln -s formatelf $out/bin/auto-formatelf
    '';
    meta = {
      description = "Modify the dynamic linker and RPATH of ELF executables";
      homepage = "https://github.com/Mic92/formatelf";
      license = lib.licenses.mit;
      maintainers = [ lib.maintainers.mic92 ];
      mainProgram = "formatelf";
      platforms = lib.platforms.linux;
    };
  };
in
makeSetupHook {
  name = "auto-formatelf-hook";
  propagatedBuildInputs = [
    formatelf
    stdenv.cc.bintools
  ];
  passthru.hideFromDocs = true;
  meta = {
    description = "Setup hook that patches ELF binaries via formatelf";
    license = lib.licenses.mit;
    maintainers = [ lib.maintainers.mic92 ];
    platforms = lib.platforms.linux;
  };
} "${src}/auto-formatelf-hook.sh"
