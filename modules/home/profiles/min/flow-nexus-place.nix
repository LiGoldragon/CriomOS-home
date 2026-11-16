# A Flow Nexus unit that starts in its place (vision:nexus-v1, "A Nexus starts
# in its place"): `slug` is the version without its dots (0533), `version`
# the dotted one (0.53.3). It is started with the place's name, `main` or
# `next`, and reads nothing at start but its Place, from its place file,
# $XDG_CONFIG_HOME/nexus/<place>/flow-nexus.signal: the place's Runtime
# (flow.sock, flow-meta.sock) and State (flow.sema). The file is written at
# every activation, with translator's nexus-configure, for it holds the user's
# runtime directory, /run/user/<uid>/nexus/<place>, which no declaration holds;
# a Nexus with no place file refuses to start, naming it, so Home always
# writes it. Nothing else reaches the unit: no environment, no other argument.
#
# Two places are two names: the stable version runs at `main`, a candidate
# at `next` with its own memory. A version becomes main by being started at
# `main`, the previous version at main having stopped; it opens main's
# memory and upgrades it in place. Every flow-facing path names the place,
# never a version: the hook settings of every Claude flow name
# $XDG_RUNTIME_DIR/nexus/main/flow.sock, the socket whichever version is
# main serves.
#
# The place's two directories are shared with every other Nexus at it and
# declared once by nexus-places.nix; the unit names no RuntimeDirectory or
# StateDirectory, is ordered after the unit that makes them, and asserts its
# place is declared.
#
# The Nexus announces readiness (READY=1 once both sockets are bound).
# Its executable opens its committed Memory configuration. The meta socket
# owns policy changes; Home provides the unit, binaries, clients and Place.
# Versioned clients share placeConfiguration, which selects that Place.
#
# The hook command it writes into every Claude flow is
# ~/.local/bin/flow-hook when this version holds the stable hook
# (stableHook): Home points that path at this version's flow-hook. Memory
# holds HarnessHook policy; the next version repoints the executable link.
{ version, slug }:
{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  optionName = "flow${slug}";
  cfg = config.criomosHome.${optionName};
  places = config.criomosHome.nexusPlaces;
  system = pkgs.stdenv.hostPlatform.system;
  home = config.home.homeDirectory;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
  # The hook command every Claude flow this Nexus launches runs, one path
  # across versions; Home points it at the version holding stableHook.
  stableHookPath = ".local/bin/flow-hook";
  # Flow <version>, built once: its executable holds no configuration.
  runtime = inputs."flow-${slug}".packages.${system}.default;
  # translator's nexus-configure, the one tool that compiles a place written
  # in datom into the place file every Nexus reads at start.
  nexusConfigure = inputs."flow-${slug}".packages.${system}.nexus-configure;
  # Place is deployment location data, encoded by the translator.
  text = value: "«${value}»";
  # The place file of this version's place, where the Nexus reads it: under
  # the user's configuration home, written at activation (it holds the user's
  # runtime directory).
  placeFile = "${config.xdg.configHome}/nexus/${cfg.place}/flow-nexus.signal";
  # The configuration home of this version's clients: its
  # nexus/flow-nexus.datom names this version's place, and the place file it
  # names is the one Home wrote, reached through a link that is read at run
  # time, so the clients and the Nexus hold one place.
  placeConfiguration =
    pkgs.runCommand "flow-${slug}-place-configuration" { } ''
      mkdir -p $out/nexus/${cfg.place}
      echo '{ ${cfg.place} }' > $out/nexus/flow-nexus.datom
      ln -s ${placeFile} $out/nexus/${cfg.place}/flow-nexus.signal
    '';
  # The <version> clients under their versioned names, reaching this
  # version's place: `flow-<version> Metaflows` is `flow
  # Metaflows` with the configuration naming this version's place.
  versionedCli =
    name: raw:
    pkgs.writeShellScript name ''
      XDG_CONFIG_HOME=${placeConfiguration} exec ${runtime}/bin/${raw} "$*"
    '';
  clients = pkgs.runCommand "flow-${slug}-clients" { } ''
    mkdir -p $out/bin
    ln -s ${versionedCli "flow-${version}" "flow"} $out/bin/flow-${version}
    ln -s ${versionedCli "flow-meta-${version}" "flow-meta"} $out/bin/flow-meta-${version}
  '';
  # The place's two directories, as the place file holds them. The runtime
  # directory is the user manager's own %t, /run/user/<uid>; a Lojix activation
  # runs without XDG_RUNTIME_DIR, so the uid names it. The state directory is
  # %S, the configured XDG state home. The directories are shared with every
  # other Nexus at the same place and declared by nexus-places.nix, so the unit
  # names no RuntimeDirectory or StateDirectory that a stop would remove.
  placeText = "{ ${text cfg.place} ${text "\${runtimeRoot}/nexus/${cfg.place}"} ${text "${config.xdg.stateHome}/nexus/${cfg.place}"} }";
in
{
  options.criomosHome.${optionName} = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = builtins.elem "AgentStack" user.capabilities;
    };
    unit = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "flow-nexus-${slug}";
    };
    place = lib.mkOption {
      type = lib.types.enum [
        "main"
        "next"
      ];
      default = "next";
      description = "The place this version runs at: main, the stable one every flow reports to, or next, a candidate with its own memory.";
    };
    stableHook = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether ~/.local/bin/flow-hook is this version's flow-hook executable; the Nexus holds its HarnessHook policy in Memory. One version holds the link at a time.";
    };
    memoryLimit = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.submodule {
          options = {
            maximum = lib.mkOption {
              type = lib.types.str;
              description = "The unit's MemoryMax: the size at which the kernel stops the Nexus.";
            };
            swapMaximum = lib.mkOption {
              type = lib.types.str;
              description = "The unit's MemorySwapMax.";
            };
          };
        }
      );
      default = null;
      description = "The memory the Nexus unit is held to; null holds it to none. It is part of the unit, so it exists only where the unit does.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = runtime;
    };
    clients = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = clients;
    };
    placeConfiguration = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = placeConfiguration;
      description = "A configuration home whose nexus/flow-nexus.datom names this version's place: its clients read their place from it.";
    };
  };
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    assertions = [
      {
        assertion = builtins.elem cfg.place places.places;
        message = "criomosHome.${optionName}.place ${cfg.place} is not one of criomosHome.nexusPlaces.places.";
      }
    ];
    home.packages = [ clients ];
    # The place file the Nexus and its clients read, written at every
    # activation: it holds the user's runtime directory, /run/user/<uid>/...,
    # which no declaration holds, and with no place file the Nexus refuses to
    # start. It is written before the units are reloaded, so a Nexus that
    # restarts at the switch finds it.
    home.activation.${"flowPlace${slug}"} = lib.hm.dag.entryBetween [ "reloadSystemd" ] [ "writeBoundary" ] ''
      runtimeRoot="/run/user/$(id -u)"
      placeDatom="$(mktemp)"
      printf '%s\n' "${placeText}" > "$placeDatom"
      run ${nexusConfigure}/bin/nexus-configure "Compile.{ «$placeDatom» «${placeFile}» }"
      rm -f "$placeDatom"
    '';
    home.file = lib.mkIf cfg.stableHook {
      ${stableHookPath}.source = "${runtime}/bin/flow-hook";
    };
    systemd.user.services.${cfg.unit} = {
      Unit = {
        Description = "Flow Nexus ${version} at ${cfg.place}";
        # The Nexus composes every launch's context through Curriculum
        # (ComposeStartup at Start, wake and resume); without it no flow starts.
        Wants = [ "curriculum-nexus.service" ];
        After = [
          "curriculum-nexus.service"
          places.unit
        ];
      };
      Service = {
        # Started once both its sockets listen: READY=1.
        Type = "notify";
        WorkingDirectory = "%h";
        ExecStart = "${runtime}/bin/flow-nexus-daemon ${cfg.place}";
        Restart = "on-failure";
        RestartSec = "100ms";
      }
      // lib.optionalAttrs (cfg.memoryLimit != null) {
        MemoryMax = cfg.memoryLimit.maximum;
        MemorySwapMax = cfg.memoryLimit.swapMaximum;
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
