{ inputs, pkgs, ... }:
# The declared Herdr server is off by default; enabled, it carries the observed
# transient unit's command line on the pinned Herdr package, and the
# activation guard refuses while another server holds the panes.
let
  inherit (pkgs) lib;
  # Regex-based string predicates refuse store-path context; compare text only.
  plain = builtins.unsafeDiscardStringContext;
  hasInfix = infix: text: lib.hasInfix (plain infix) (plain text);
  hasSuffix = suffix: text: lib.hasSuffix (plain suffix) (plain text);
  # Home Manager stores unit values as lists; read single values as text.
  text = value: if builtins.isList value then lib.concatStringsSep " " (map toString value) else toString value;
  has = entry: value: lib.elem entry (lib.toList value);
  mkHome =
    extraModule:
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs;
        user = {
          size = "Min";
          useColemak = false;
          hasPublicKey = false;
          gitSigningKey = "";
          matrixId = "";
          isMultimediaDev = false;
          emailAddress = "herdr-server-check@example.invalid";
          githubId = "herdr-server-check";
          name = "herdr-server-check";
          publicKeys = [ ];
        };
        horizon.node = {
          name = "herdr-server-check";
          machine.architecture = "x86_64";
        };
        hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
        rustToolchain = pkgs.rustc;
      };
      modules = [
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/default.nix
        {
          home = {
            username = "herdr-server-check";
            homeDirectory = "/home/herdr-server-check";
            stateVersion = "26.11";
          };
        }
        extraModule
      ];
    };
  off = (mkHome { }).config;
  on = (mkHome { criomosHome.herdr.server.enable = true; }).config;
  service = on.systemd.user.services.herdr-server;
  herdrPackage = on.criomosHome.herdr.package;
  checks = [
    {
      ok = !(off.systemd.user.services ? herdr-server) && !(off.home.activation ? herdrServerHandoverGuard);
      msg = "herdr-server is declared while criomosHome.herdr.server.enable is off";
    }
    {
      ok = on.criomosHome.herdr.versionPin == "0.8.2" && herdrPackage.version == on.criomosHome.herdr.versionPin;
      msg = "the Herdr package does not match the 0.8.2 version pin";
    }
    {
      ok =
        (text service.Service.ExecStart) == "${herdrPackage}/bin/herdr server"
        && (text service.Service.Type) == "exec"
        && (text service.Service.Restart) == "no"
        && (text service.Service.KillMode) == "control-group"
        && (text service.Service.Slice) == "app.slice"
        && (text service.Service.WorkingDirectory) == "%h"
        && (text service.Service.Environment) == ""
        && service.Install.WantedBy == [ "default.target" ];
      msg = "herdr-server unit contents differ from the observed transient unit";
    }
    {
      ok =
        hasInfix "pgrep" on.home.activation.herdrServerHandoverGuard.data
        && hasInfix "exit 1" on.home.activation.herdrServerHandoverGuard.data
        && lib.elem "writeBoundary" on.home.activation.herdrServerHandoverGuard.before;
      msg = "herdr-server handover guard missing or not before writeBoundary";
    }
  ];
  failures = lib.filter (check: !check.ok) checks;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (check: check.msg) failures)
else
  pkgs.runCommand "herdr-server" { } ''
    set -eu
    test -x ${herdrPackage}/bin/herdr
    ${herdrPackage}/bin/herdr --version | grep -qx 'herdr 0.8.2'
    touch $out
  ''
