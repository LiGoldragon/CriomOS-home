{ pkgs, inputs, ... }:
assert inputs ? flow-next;
let
  module = import ../../modules/home/profiles/min/flow-message-next.nix {
    lib = pkgs.lib;
    config.criomosHome.flowMessageNext.enable = false;
  };
in
assert !module.options.criomosHome.flowMessageNext.enable.default;
assert (builtins.head module.config.assertions).assertion;
assert !(module.config ? systemd);
assert !(module.config ? home);
pkgs.runCommand "flow-preview-retired" { } "mkdir -p $out"
