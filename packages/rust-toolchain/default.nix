{ inputs, pkgs, ... }:

(inputs.rust-overlay.lib.mkRustBin { } pkgs).stable."1.96.0".minimal.override {
  extensions = [
    "rust-src"
    "rust-analyzer"
    "rustfmt"
    "clippy"
  ];
}
