{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.158.0-alpha.9";
  targets = {
    x86_64-linux = {
      hash = "sha256-r6jIHXWayHDyGbTKysFbpa1qERB7W3sQXI2Cg7jRFnw=";
      hostHash = "sha256-CqTxMWD+Y4QmGMt8JHTw7bKNaN8lKiPWPuh0u0apP1Q=";
    };
    aarch64-linux = {
      hash = "sha256-e202MgQU0Atua8WVlJJ/rIYksCL6j9hNMw3zOoYqPxA=";
      hostHash = "sha256-b77gtc0Hn8RGplFvIaCIs5+o7keUbfE+Hn+dH+AT+88=";
    };
  };
in
(import ../../lib/mk-codex-prebuilt.nix { inherit lib stdenvNoCC fetchurl; }) {
  pname = "codex-next";
  inherit version targets;
  description = "Pinned upstream Codex candidate for the isolated next server";
}
