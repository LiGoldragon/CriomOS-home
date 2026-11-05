{
  lib,
  stdenvNoCC,
  fetchurl,
}:
let
  version = "0.161.0-alpha.2";
  targets = {
    x86_64-linux = {
      hash = "sha256-Vfht8jbnRC2IwhWGfVMngXX85155T52yCpZ7ae5MqOk=";
      hostHash = "sha256-InR44u5W9CKTSx12FtmbUil7zTwA7v7rsS2c0QKmWyg=";
    };
    aarch64-linux = {
      hash = "sha256-wmv0qdFeeKv7HuafcHQT8wfvN1UrSb+QmyVxcwgNIBE=";
      hostHash = "sha256-jg8pNsA8RchH+2lWq60fPPTxGwtZt6YIMOFxJG5xj18=";
    };
  };
in
(import ../../lib/mk-codex-prebuilt.nix { inherit lib stdenvNoCC fetchurl; }) {
  pname = "codex-next-candidate";
  inherit version targets;
  description = "Pinned upstream Codex candidate for a separately identified next endpoint";
}
