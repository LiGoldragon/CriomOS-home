# A service that runs as a stable and a next side by side.
#
# Every Nexus derives its whole default layout from two anchors: HOME (its
# `.sema` store under `.local/state/<name>/`) and XDG_RUNTIME_DIR (its sockets
# under `<name>/`). The stable instance keeps the real anchors. The next
# instance gets anchors of its own, so the same executable, started with no
# arguments, lands on a fresh store and on sockets that cannot collide with
# stable's:
#
#   stable  HOME=~                          sockets %t/<name>/…
#   next    HOME=~/.local/state/<name>-next sockets %t/<name>-next/<name>/…
#
# Rolling: point stable's package at next's once next is trusted, move the
# callers to the stable socket, and the next slot is free for the next
# version. The same unit body (a function of an instance) serves either slot.
#
# Changing HOME and XDG_RUNTIME_DIR reaches the Nexus's own children too, so
# the next instance re-exports the user's real XDG homes (`anchorEnvironment`):
# a child that finds its own server through them (Herdr through
# XDG_CONFIG_HOME, for one) still finds the one the user runs.
{ lib, pkgs }:
let
  inherit (lib) concatMapStringsSep escapeShellArg mapAttrsToList removePrefix;

  # `name` is the Nexus's own directory name (flow, message); `unit` its
  # systemd unit stem (flow-nexus); `sockets` maps each socket to its file
  # name, its client's socket variable, and its client executable.
  instance =
    {
      name,
      unit,
      package,
      sockets,
      homeDirectory,
      slot,
      peers ? { },
    }:
    let
      next = slot == "next";
      slotName = if next then "${name}-next" else name;
      runtimeAnchor = if next then "%t/${slotName}" else "%t";
      shellRuntime = "\${XDG_RUNTIME_DIR:-/run/user/$(id -u)}";
      shellAnchor = if next then "${shellRuntime}/${slotName}" else shellRuntime;
      homeAnchor = if next then "${homeDirectory}/.local/state/${slotName}" else homeDirectory;
      socketPath = anchor: file: "${anchor}/${name}/${file}";
    in
    rec {
      inherit
        name
        slot
        slotName
        package
        homeAnchor
        runtimeAnchor
        ;
      # The unit stem with the slot suffix: flow-nexus, flow-nexus-next.
      unitName = stem: if next then "${stem}-next" else stem;
      serviceUnit = unitName unit;
      # The unit's RuntimeDirectory: the stable Nexus's socket directory, or
      # the next instance's whole runtime anchor.
      runtimeDirectory = slotName;
      stateDirectory = "${homeAnchor}/.local/state/${name}";
      # Socket paths as systemd sees them (%t) and as a shell client sees them.
      socket = builtins.mapAttrs (_: value: socketPath runtimeAnchor value.file) sockets;
      shellSocket = builtins.mapAttrs (_: value: socketPath shellAnchor value.file) sockets;
      # The anchors a next Nexus runs under; stable adds nothing.
      anchorEnvironment =
        if next then
          [
            "HOME=${homeAnchor}"
            "XDG_RUNTIME_DIR=${runtimeAnchor}"
            "XDG_CONFIG_HOME=${homeDirectory}/.config"
            "XDG_DATA_HOME=${homeDirectory}/.local/share"
            "XDG_STATE_HOME=${homeDirectory}/.local/state"
            "XDG_CACHE_HOME=${homeDirectory}/.cache"
          ]
        else
          [ ];
      # A next Nexus reaches its peers at their default relative location in
      # its own runtime anchor; each peer's socket directory is linked there
      # before start. `peers` maps a peer name to that peer's instance.
      # The script takes the real runtime directory (%t) as its argument.
      peerLinks = pkgs.writeShellScript "${serviceUnit}-peer-links" ''
        set -eu
        runtime="$1"
        ${concatMapStringsSep "\n" (
          peer:
          "${pkgs.coreutils}/bin/ln -sfn \"$runtime/${peer.slotName}/${peer.name}\" \"$runtime/${slotName}/${peer.name}\""
        ) (builtins.attrValues peers)}
      '';
      # Clients: stable keeps the package's own names; next gets
      # `<name>-next<rest>` wrappers (flow-meta → flow-next-meta) with the
      # socket variable preselected, so callers choose by name.
      clientName = client: if next then "${name}-next${removePrefix name client}" else client;
      clients = pkgs.runCommand "${slotName}-clients" { nativeBuildInputs = [ pkgs.makeWrapper ]; } ''
        mkdir -p $out/bin
        ${lib.concatStringsSep "\n" (
          mapAttrsToList (_: value: ''
            makeWrapper ${package}/bin/${value.client} $out/bin/${clientName value.client} \
              --run ${escapeShellArg "export ${value.variable}=\"${socketPath shellAnchor value.file}\""}
          '') sockets
        )}
      '';
    };
in
{
  inherit instance;

  # The pair: two instances of one service, differing only in slot and
  # package. `peers` names the next instances a next instance reaches.
  pair =
    {
      stablePackage,
      nextPackage,
      nextPeers ? { },
      ...
    }@arguments:
    let
      common = builtins.removeAttrs arguments [
        "stablePackage"
        "nextPackage"
        "nextPeers"
      ];
    in
    {
      stable = instance (
        common
        // {
          package = stablePackage;
          slot = "stable";
        }
      );
      next = instance (
        common
        // {
          package = nextPackage;
          slot = "next";
          peers = nextPeers;
        }
      );
    };
}
