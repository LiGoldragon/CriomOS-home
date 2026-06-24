{ inputs, pkgs, ... }:

let
  craneLib = inputs.crane.mkLib pkgs;

  commonArguments = {
    pname = "mentci";
    version = "0.1.0";
    src = craneLib.cleanCargoSource inputs.mentci-src;

    strictDeps = true;
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArguments;
in
craneLib.buildPackage (
  commonArguments
  // {
    inherit cargoArtifacts;

    meta = {
      description = "Mentci daemon and CLI for the human approval surface";
      homepage = "https://github.com/LiGoldragon/mentci";
      license = pkgs.lib.licenses.mit;
      mainProgram = "mentci";
      platforms = pkgs.lib.platforms.linux;
    };
  }
)
