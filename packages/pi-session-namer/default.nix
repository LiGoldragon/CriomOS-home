{ inputs, pkgs, ... }:

inputs.pi-session-namer.packages.${pkgs.stdenv.hostPlatform.system}.pi-session-namer
