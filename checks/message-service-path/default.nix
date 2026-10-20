{ inputs, pkgs, ... }:
let
  deployment = pkgs.callPackage ../../packages/message-deployment { inherit inputs; };
  runtime = inputs.message.packages.${pkgs.stdenv.hostPlatform.system}.default;

  # Evaluate the real Message module independently of runtime realization.
  selection =
    {
      flowEnabled,
      messageEnabled ? null,
      size ? "Min",
    }:
    let
      evaluated = pkgs.lib.evalModules {
        specialArgs = {
          inherit inputs pkgs;
          user = {
            name = "fixture";
            inherit size;
          };
        };
        modules = [
          ({ lib, ... }: {
            options = {
              criomosHome.flow.enable = lib.mkOption {
                type = lib.types.bool;
                default = flowEnabled;
              };
              home.packages = lib.mkOption {
                type = lib.types.listOf lib.types.package;
                default = [ ];
              };
              systemd.user.services = lib.mkOption {
                type = lib.types.attrsOf lib.types.anything;
                default = { };
              };
              assertions = lib.mkOption {
                type = lib.types.listOf lib.types.anything;
                default = [ ];
              };
            };
          })
          ../../modules/home/profiles/min/message.nix
          (pkgs.lib.optionalAttrs (messageEnabled != null) {
            criomosHome.message.enable = messageEnabled;
          })
        ];
      };
      cfg = evaluated.config;
    in
    {
      enabled = cfg.criomosHome.message.enable;
      services = builtins.attrNames cfg.systemd.user.services;
      assertionsPassed = builtins.all (item: item.assertion) cfg.assertions;
      requires = cfg.systemd.user.services.message-nexus.Unit.Requires or [ ];
      after = cfg.systemd.user.services.message-nexus.Unit.After or [ ];
      partOf = cfg.systemd.user.services.message-nexus.Unit.PartOf or [ ];
      wantedBy = cfg.systemd.user.services.message-nexus.Install.WantedBy or [ ];
    };
  paired = selection { flowEnabled = true; };
  unpaired = selection { flowEnabled = false; };
  explicitUnsupported = selection {
    flowEnabled = false;
    messageEnabled = true;
  };
  explicitOff = selection {
    flowEnabled = true;
    messageEnabled = false;
  };
  explicitOn = selection {
    flowEnabled = true;
    messageEnabled = true;
  };
  explicitOffUnpaired = selection {
    flowEnabled = false;
    messageEnabled = false;
  };
  belowMin = selection {
    flowEnabled = true;
    size = "Zero";
  };
in
assert paired.enabled && paired.assertionsPassed;
assert paired.services == [ "message-nexus" ];
assert paired.requires == [ "flow-nexus.service" ];
assert paired.after == [ "flow-nexus.service" ];
# A flow-nexus start or restart starts or restarts Message with it.
assert paired.partOf == [ "flow-nexus.service" ];
assert builtins.elem "flow-nexus.service" paired.wantedBy;
assert !unpaired.enabled && unpaired.services == [ ] && unpaired.assertionsPassed;
assert explicitUnsupported.enabled && !explicitUnsupported.assertionsPassed;
assert !explicitOff.enabled && explicitOff.services == [ ] && explicitOff.assertionsPassed;
assert explicitOn == paired;
assert explicitOffUnpaired == unpaired;
assert belowMin.services == [ ] && belowMin.assertionsPassed;
assert !(inputs ? message-next);
pkgs.runCommand "message-service-path"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
  }
  ''
    for name in message message-meta message-nexus; do
      test "$(readlink -f ${deployment}/bin/$name)" = "${runtime}/bin/$name"
    done
    test ! -e ${deployment}/share
    test "$(${deployment}/bin/message --version | awk '{print $NF}')" = "$(${deployment}/bin/message-nexus --version | awk '{print $NF}')"
    mkdir -p "$out"
  ''
