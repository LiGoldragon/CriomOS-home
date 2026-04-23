{ pkgs, ... }:
pkgs.mkShell {
  packages = [
    pkgs.nixfmt-rfc-style
    pkgs.jq
  ];
}
