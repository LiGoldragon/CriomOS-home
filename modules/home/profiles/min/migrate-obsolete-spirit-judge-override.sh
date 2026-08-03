if [ "$#" -ne 1 ]; then
  printf '%s\n' 'usage: migrate-obsolete-spirit-judge-override OVERRIDE_PATH' >&2
  exit 64
fi

override_path=$1

# Absence is the steady state after the one-time migration.
if [ ! -e "$override_path" ] && [ ! -L "$override_path" ]; then
  exit 0
fi

refuse() {
  printf 'refusing to remove unrecognized Spirit judge override: %s\n' "$override_path" >&2
  exit 65
}

# Never follow or remove a symlink, directory, device, or other non-regular
# object at the systemd drop-in path.
if [ -L "$override_path" ] || [ ! -f "$override_path" ]; then
  refuse
fi

mapfile -t override_lines < "$override_path"
if [ "${#override_lines[@]}" -ne 3 ]; then
  refuse
fi

if [ "${override_lines[0]}" != '[Service]' ] || [ "${override_lines[1]}" != 'ExecStart=' ]; then
  refuse
fi

obsolete_exec=${override_lines[2]#ExecStart=}
if [ "$obsolete_exec" = "${override_lines[2]}" ]; then
  refuse
fi

if [[ ! ${override_lines[2]} =~ ^ExecStart=/nix/store/[0-9a-z]{32}-spirit-judge-daemon-service/bin/spirit-judge-daemon-service$ ]]; then
  refuse
fi

# The predicate is intentionally for a collected executable only. A still-live
# executable or even a remaining symlink is not obsolete state this migration
# owns, so activation stops for operator review.
if [ -e "$obsolete_exec" ] || [ -L "$obsolete_exec" ]; then
  refuse
fi

rm -- "$override_path"
