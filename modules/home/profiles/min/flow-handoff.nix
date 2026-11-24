# A release supplies the two immutable writer coordinates and the direction.
# The counterpart's inert declaration keeps the stopped invocation visible to
# the user manager and removes its automatic start. Only the selected version
# can acquire the shared store lock and open main.
{ departure, arrival, action, selected }:
{
  config,
  inputs,
  lib,
  pkgs,
  user,
  ...
}:
let
  cfg = config.criomosHome.${selected.option};
  system = pkgs.stdenv.hostPlatform.system;
  package = inputs.${selected.input}.packages.${system}.default;
  opposite = if selected.unit == arrival.unit then departure else arrival;
  guard = "flow-handoff-${departure.slug}-${arrival.slug}-${action}";
  state = "%S/nexus/${cfg.place}";
  runtime = "%t/nexus/${cfg.place}";
  places = config.criomosHome.nexusPlaces;
  sizeAtLeast = (import ../../../../lib/horizon-user.nix { inherit lib; }).sizeAtLeast user.size;
in
{
  config = lib.mkIf (sizeAtLeast "Min" && cfg.enable) {
    systemd.user.services = {
      ${opposite.unit} = {
        Unit = {
          Description = "Fenced Flow predecessor or successor at ${cfg.place}";
          "X-SwitchMethod" = "keep-old";
          RefuseManualStart = true;
        };
        Service.ExecStart = "${pkgs.coreutils}/bin/false";
      };
      ${guard} = {
        Unit = {
          Description = "Verify Flow stopped-store ${action} at ${cfg.place}";
          After = [ "${opposite.unit}.service" places.unit ];
          Conflicts = [ "${opposite.unit}.service" ];
          Before = [ "${selected.unit}.service" ];
        };
        Service = {
          Type = "oneshot";
          UMask = "0077";
          ExecStart = lib.escapeShellArgs [
            "${pkgs.python3}/bin/python3"
            "${../../../../lib/flow-handoff.py}"
            action
            "${pkgs.systemd}/bin/systemctl"
            state runtime
            "${departure.unit}.service" "${arrival.unit}.service"
            departure.revision arrival.revision
          ];
        };
      };
      ${selected.unit} = {
        Unit = {
          After = [ "${opposite.unit}.service" "${guard}.service" ];
          Conflicts = [ "${opposite.unit}.service" ];
          Requires = [ "${guard}.service" ];
        };
        Service.ExecStart = lib.mkForce (lib.escapeShellArgs [
          "${pkgs.util-linux}/bin/flock" "--no-fork" "--nonblock"
          "${state}/flow-writer.lock" "${package}/bin/flow-nexus-daemon" cfg.place
        ]);
      };
    };
  };
}
