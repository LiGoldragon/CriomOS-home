{
  pkgs,
  lib,
  horizon,
  ...
}:
let
  inherit (horizon.node) behavesAs;

  uiPriorityApply = pkgs.writeShellScriptBin "criomos-ui-priority-apply" ''
    set -eu

    dry_run="''${CRIOMOS_UI_PRIORITY_DRY_RUN:-0}"

    log() {
      printf '%s\n' "$*"
    }

    apply_to_unit() {
      unit_name="$1"
      shift

      load_state="$(${pkgs.systemd}/bin/systemctl --user show "$unit_name" --property=LoadState --value 2>/dev/null || true)"
      if [ "$load_state" = "" ] || [ "$load_state" = "not-found" ]; then
        log "skip unit=$unit_name reason=not-found"
        return 0
      fi

      if [ "$dry_run" = "1" ]; then
        log "dry-run unit=$unit_name properties=$*"
        return 0
      fi

      if ${pkgs.systemd}/bin/systemctl --user set-property --runtime "$unit_name" "$@" >/dev/null 2>&1; then
        log "protected unit=$unit_name"
      else
        log "failed unit=$unit_name"
      fi
    }

    unit_from_process() {
      process_identifier="$1"
      cgroup_file="/proc/$process_identifier/cgroup"
      [ -r "$cgroup_file" ] || return 0
      ${pkgs.gnused}/bin/sed -n 's#^0::.*/##p' "$cgroup_file" | ${pkgs.coreutils}/bin/head -n1
    }

    process_command_line() {
      process_identifier="$1"
      command_file="/proc/$process_identifier/cmdline"
      [ -r "$command_file" ] || return 0
      ${pkgs.coreutils}/bin/tr '\0' ' ' < "$command_file"
    }

    protect_matching_process_scopes() {
      match_expression="$1"
      shift
      seen_units=" "

      for process_directory in /proc/[0-9]*; do
        process_identifier="''${process_directory#/proc/}"
        owner_identifier="$(${pkgs.coreutils}/bin/stat -c %u "$process_directory" 2>/dev/null || true)"
        [ "$owner_identifier" = "$UID" ] || continue

        command_line="$(process_command_line "$process_identifier" || true)"
        [ -n "$command_line" ] || continue

        if printf '%s\n' "$command_line" | ${pkgs.gnugrep}/bin/grep -E -q "$match_expression"; then
          unit_name="$(unit_from_process "$process_identifier" || true)"
          [ -n "$unit_name" ] || continue
          case "$seen_units" in
            *" $unit_name "*) continue ;;
          esac
          seen_units="$seen_units$unit_name "
          apply_to_unit "$unit_name" "$@"
        fi
      done
    }

    # Stable session services: apply runtime cgroup properties only.
    # Do not own or restart the live parent session slice.
    apply_to_unit niri.service \
      CPUWeight=1000 \
      IOAccounting=yes \
      IOWeight=1000 \
      MemoryAccounting=yes \
      MemoryLow=512M

    apply_to_unit dbus-broker.service \
      CPUWeight=800 \
      IOAccounting=yes \
      IOWeight=800 \
      MemoryAccounting=yes \
      MemoryLow=128M

    apply_to_unit xdg-desktop-portal.service \
      CPUWeight=700 \
      IOAccounting=yes \
      IOWeight=700 \
      MemoryAccounting=yes \
      MemoryLow=128M

    apply_to_unit xdg-desktop-portal-gtk.service \
      CPUWeight=700 \
      IOAccounting=yes \
      IOWeight=700 \
      MemoryAccounting=yes \
      MemoryLow=128M

    apply_to_unit xdg-document-portal.service \
      CPUWeight=600 \
      IOAccounting=yes \
      IOWeight=600 \
      MemoryAccounting=yes \
      MemoryLow=64M

    apply_to_unit xdg-permission-store.service \
      CPUWeight=600 \
      IOAccounting=yes \
      IOWeight=600 \
      MemoryAccounting=yes \
      MemoryLow=64M

    apply_to_unit pipewire.service \
      CPUWeight=700 \
      IOAccounting=yes \
      IOWeight=700 \
      MemoryAccounting=yes \
      MemoryLow=128M

    apply_to_unit wireplumber.service \
      CPUWeight=700 \
      IOAccounting=yes \
      IOWeight=700 \
      MemoryAccounting=yes \
      MemoryLow=128M

    # App-scope components have transient names. Match the running process
    # command line and protect that specific scope only.
    protect_matching_process_scopes '(^|/| )noctalia( |$)' \
      CPUWeight=900 \
      IOAccounting=yes \
      IOWeight=900 \
      MemoryAccounting=yes \
      MemoryLow=256M

    protect_matching_process_scopes '(^|/| )mako( |$)' \
      CPUWeight=600 \
      IOAccounting=yes \
      IOWeight=600 \
      MemoryAccounting=yes \
      MemoryLow=64M
  '';

  uiPriorityStatus = pkgs.writeShellScriptBin "criomos-ui-priority-status" ''
    set -eu

    show_unit() {
      unit_name="$1"
      load_state="$(${pkgs.systemd}/bin/systemctl --user show "$unit_name" --property=LoadState --value 2>/dev/null || true)"
      if [ "$load_state" = "" ] || [ "$load_state" = "not-found" ]; then
        printf 'unit=%s state=not-found\n' "$unit_name"
        return 0
      fi

      ${pkgs.systemd}/bin/systemctl --user show "$unit_name" \
        --property=Id \
        --property=LoadState \
        --property=ActiveState \
        --property=CPUWeight \
        --property=IOWeight \
        --property=MemoryLow \
        --property=MemoryCurrent \
        --property=ControlGroup \
        --no-pager
    }

    for unit_name in \
      niri.service \
      dbus-broker.service \
      xdg-desktop-portal.service \
      xdg-desktop-portal-gtk.service \
      xdg-document-portal.service \
      xdg-permission-store.service \
      pipewire.service \
      wireplumber.service
    do
      show_unit "$unit_name"
      printf '\n'
    done
  '';
in
{
  config = lib.mkIf behavesAs.edge {
    home.packages = [
      uiPriorityApply
      uiPriorityStatus
    ];

    systemd.user.services.criomos-ui-priority = {
      Unit = {
        Description = "Apply runtime resource priority to desktop recovery components";
        After = [
          "graphical-session.target"
          "niri.service"
          "dbus-broker.service"
        ];
      };
      Install.WantedBy = [ "graphical-session.target" ];
      Service = {
        Type = "oneshot";
        ExecStart = "${uiPriorityApply}/bin/criomos-ui-priority-apply";
      };
    };
  };
}
