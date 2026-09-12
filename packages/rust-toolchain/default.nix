{ inputs, pkgs, ... }:

(inputs.rust-overlay.lib.mkRustBin { } pkgs).stable."1.97.1".minimal.override {
  extensions = [
    "rust-src"
    "rust-analyzer"
    "rustfmt"
    "clippy"
  ];
}
