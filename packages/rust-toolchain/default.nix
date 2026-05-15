{ inputs, pkgs, ... }:

(inputs.rust-overlay.lib.mkRustBin { } pkgs).stable.latest.minimal.override {
  extensions = [
    "rust-src"
    "rust-analyzer"
    "rustfmt"
    "clippy"
  ];
}
