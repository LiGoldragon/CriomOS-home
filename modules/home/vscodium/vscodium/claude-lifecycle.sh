#!/usr/bin/env bash
set -euf
export LC_ALL=C

path_error() { printf 'criomos-codium: invalid %s path\n' "$1" >&2; exit 64; }
valid_absolute_path() {
  [ -n "$1" ] || return 1
  case "$1" in /*) ;; *) return 1 ;; esac
  case "$1" in *$'\n'*|*$'\r'*|*[[:cntrl:]]*|*'//'*) return 1 ;; esac
  case "/$1/" in */./*|*/../*) return 1 ;; esac
}
canonical_existing_path() {
  path_probe="$1"
  while [ ! -e "$path_probe" ] && [ ! -L "$path_probe" ]; do
    path_probe="${path_probe%/*}"
  done
  [ -n "$path_probe" ] || return 1
  [ "$path_probe" = "$1" ] || [ -d "$path_probe" ] || return 1
  [ "$(@READLINK@ -f "$path_probe" 2>/dev/null || true)" = "$path_probe" ]
}
direct_child_of() {
  parent="$1" child="$2"
  case "$child" in "$parent"/*) leaf="${child#"$parent"/}" ;; *) return 1 ;; esac
  [ -n "$leaf" ] && [[ "$leaf" != */* ]]
}
home_dir="${HOME:-}"
if [ "${XDG_STATE_HOME+x}" = x ]; then
  xdg_state_home="$XDG_STATE_HOME"
  valid_absolute_path "$xdg_state_home" || path_error XDG_STATE_HOME
fi
if [ "${CRIOMOS_VSCODIUM_EXTENSIONS_DIR+x}" = x ]; then
  ext_dir="$CRIOMOS_VSCODIUM_EXTENSIONS_DIR"
else
  valid_absolute_path "$home_dir" || path_error HOME
  ext_dir="$home_dir/.vscode-oss/extensions"
fi
if [ "${CRIOMOS_VSCODIUM_STATE_DIR+x}" = x ]; then
  state_dir="$CRIOMOS_VSCODIUM_STATE_DIR"
elif [ "${XDG_STATE_HOME+x}" = x ]; then
  state_dir="$xdg_state_home/criomos/vscodium-claude"
else
  valid_absolute_path "$home_dir" || path_error HOME
  state_dir="$home_dir/.local/state/criomos/vscodium-claude"
fi
# Nix records an automatic GC root for each --add-root user path. Keep that
# path in the user's state directory: activation never creates anything in
# /nix, while the daemon retains the target through its automatic-root tree.
if [ "${CRIOMOS_VSCODIUM_GCROOT_DIR+x}" = x ]; then
  root_dir="$CRIOMOS_VSCODIUM_GCROOT_DIR"
else
  root_dir="$state_dir/gcroots"
fi
if [ "${CRIOMOS_VSCODIUM_LOCK_FILE+x}" = x ]; then
  lock_file="$CRIOMOS_VSCODIUM_LOCK_FILE"
else
  lock_file="$state_dir/lifecycle.lock"
fi
valid_absolute_path "$ext_dir" && canonical_existing_path "$ext_dir" || path_error extensions
[ ! -e "$ext_dir" ] || [ -d "$ext_dir" ] || path_error extensions
valid_absolute_path "$state_dir" && canonical_existing_path "$state_dir" || path_error state
valid_absolute_path "$root_dir" && direct_child_of "$state_dir" "$root_dir" \
  && canonical_existing_path "$root_dir" || path_error gcroot
valid_absolute_path "$lock_file" && direct_child_of "$state_dir" "$lock_file" \
  && canonical_existing_path "$lock_file" || path_error "lock ($lock_file)"
manifest="$state_dir/manifest"
registry="$ext_dir/extensions.json"
dry=0
bootstrap_only=0
nix_store="${CRIOMOS_VSCODIUM_NIX_STORE:-@NIX_STORE@}"
codium="${CRIOMOS_VSCODIUM_CODIUM:-@CODIUM@}"
systemctl="${CRIOMOS_VSCODIUM_SYSTEMCTL:-@SYSTEMCTL@}"
for runtime_command in "$nix_store" "$codium" "$systemctl"; do
  case "$runtime_command" in
    /*) [ -x "$runtime_command" ] || exit 127 ;;
    *) exit 127 ;;
  esac
done
for arg in "$@"; do [ "$arg" = --bootstrap ] && bootstrap_only=1; done
for arg in "$@"; do [ "$arg" = --dry-run ] && dry=1; done
mutate() { if [ "$dry" -eq 1 ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
validate_mutation_paths() {
  canonical_existing_path "$state_dir" && [ -d "$state_dir" ] || path_error state
  canonical_existing_path "$root_dir" && [ -d "$root_dir" ] || path_error gcroot
  canonical_existing_path "$lock_file" || path_error "lock ($lock_file)"
}
mkdir_state() {
  [ "$dry" -eq 1 ] && return 0
  @COREUTILS@/bin/mkdir -p "$state_dir" "$root_dir"
  validate_mutation_paths
}
valid_target() {
  case "$1" in /nix/store/*) ;; *) return 1;; esac
  [ -e "$1" ] && [ "$(@READLINK@ -f "$1" 2>/dev/null || true)" = "$1" ]
}
# The manifest is mutable user state.  Keep its names to the exact basename
# form owned by this lifecycle: no path separators, controls, or locale-wide
# character classes can reach a filesystem operation.
valid_version() {
  [[ "$1" =~ ^[0-9]+[.][0-9]+[.][0-9]+(-[0-9A-Za-z-]+([.][0-9A-Za-z-]+)*)?([+][0-9A-Za-z-]+([.][0-9A-Za-z-]+)*)?$ ]]
}
valid_link_name() {
  [[ "$1" =~ ^anthropic[.]claude-code-[0-9]+[.][0-9]+[.][0-9]+(-[0-9A-Za-z-]+([.][0-9A-Za-z-]+)*)?([+][0-9A-Za-z-]+([.][0-9A-Za-z-]+)*)?-linux-x64$ ]]
}
valid_manifest_entry() {
  [ "$1" = managed ] && valid_version "$2" && valid_link_name "$3" \
    && [ "$3" = "anthropic.claude-code-$2-linux-x64" ] && valid_target "$4"
}
register_root() {
  # Repair a missing automatic root even when the visible link already resolves
  # to the target (for example after an interrupted cleanup).
  mutate "$nix_store" --add-root "$1" --realise "$2" >/dev/null
}
root_retains_target() {
  root_target="$(@READLINK@ -f "$1" 2>/dev/null || true)"
  valid_target "$root_target" || return 1
  case "$2" in "$root_target"|"$root_target"/*) return 0;; *) return 1;; esac
}
manifest_is_valid() {
  manifest_valid=1; seen_names=""; manifest_header="$(@COREUTILS@/bin/head -n1 "$manifest" || true)"
  # Bash strings cannot retain NULs, so reject them before line parsing rather
  # than allowing the shell to silently reinterpret a byte stream.
  [ "$(@COREUTILS@/bin/wc -c < "$manifest")" = "$(@COREUTILS@/bin/tr -d '\000' < "$manifest" | @COREUTILS@/bin/wc -c)" ] || return 1
  case "$manifest_header" in v1|v1-bootstrap|v1-ready) ;; *) return 1;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    tabs="${line//[^$'\t']/}"
    [ "${#tabs}" -eq 3 ] || { manifest_valid=0; break; }
    IFS=$'\t' read -r owner ver name tgt extra <<< "$line"
    [ -z "$extra" ] && valid_manifest_entry "$owner" "$ver" "$name" "$tgt" || { manifest_valid=0; break; }
    case " $seen_names " in *" $name "*) manifest_valid=0; break;; esac
    seen_names="$seen_names $name"
    [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] || { manifest_valid=0; break; }
    [ -L "$root_dir/$name" ] && root_retains_target "$root_dir/$name" "$tgt" || { manifest_valid=0; break; }
  done < <(@COREUTILS@/bin/tail -n +2 "$manifest")
  [ "$manifest_valid" -eq 1 ]
}

managed_extension() {
  managed="$ext_dir/anthropic.claude-code"
  [ -d "$ext_dir" ] && [ -e "$managed/package.json" ] || return 1
  version="$(@JQ@ -er '.version | strings' "$managed/package.json")" || return 1
  valid_version "$version" || return 1
  target="$(@READLINK@ -f "$managed")"; valid_target "$target" || return 1
  desired="anthropic.claude-code-$version-linux-x64"
  valid_link_name "$desired" || return 1
}

# The Home Manager vscode module uses this exact supported refresh sequence.
# Never edit extensions.json ourselves: it is Codium's mutable registry and
# may contain entries that Home Manager does not own.
registry_is_current() {
  [ -f "$registry" ] && @JQ@ -e \
    --arg id anthropic.claude-code \
    --arg path "$ext_dir/$desired" \
    'type == "array" and any(.[]; .identifier.id? == $id and .location.path? == $path)' \
    "$registry" >/dev/null 2>&1
}

refresh_registry() {
  managed_extension || return 1
  [ -L "$ext_dir/$desired" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$desired" 2>/dev/null || true)" = "$target" ] || return 1
  registry_is_current && return 0
  backup="$registry.criomos-backup.$$"
  if [ -e "$registry" ]; then
    @COREUTILS@/bin/cp -p "$registry" "$backup" || return 1
  fi
  @COREUTILS@/bin/rm -f "$registry" "$ext_dir/.init-default-profile-extensions"
  if CRIOMOS_VSCODIUM_REGISTRY_BACKUP="$backup" "$codium" --list-extensions >/dev/null 2>&1 && registry_is_current; then
    @COREUTILS@/bin/rm -f "$backup"
    return 0
  fi
  # A failed refresh must not discard mutable registry state. Restoring the
  # whole prior registry is deliberately the only JSON operation here.
  [ ! -e "$backup" ] || @COREUTILS@/bin/mv -f "$backup" "$registry"
  return 1
}

launch_ready() {
  managed_extension \
    && [ -L "$ext_dir/$desired" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$desired" 2>/dev/null || true)" = "$target" ] \
    && [ -f "$manifest" ] \
    && [ "$(@COREUTILS@/bin/head -n1 "$manifest")" = v1 ]
}

prepare_launch() {
  # Fresh state intentionally progresses through bootstrap and ready first.
  # Under the wrapper's EX lease it is safe to complete those bounded stages
  # before any GUI process can observe the extension directory.
  reconcile --launch
  launch_ready || reconcile --launch
  launch_ready || reconcile --launch
  launch_ready || return 1
  refresh_registry
}

activation_refresh() {
  # An immutable extension declaration may change while a GUI session owns SH.
  # Do not make Home Manager wait for that session; its next launch will do the
  # same convergence under EX. Keep the supported registry refresh inside the
  # one nonblocking EX lease when an activation is able to perform it.
  mkdir_state
  exec 9>"$lock_file"
  @FLOCK@ -xn 9 || return 0
  CRIOMOS_VSCODIUM_LOCK_HELD=1 reconcile --activate
  launch_ready || return 0
  refresh_registry
}

valid_scope_unit() {
  [[ "$1" =~ ^criomos-vscodium-[0-9]+-[0-9]+[.]scope$ ]]
}

valid_session_ready() {
  candidate="$1"
  candidate_parent="${candidate%/*}"
  candidate_leaf="${candidate##*/}"
  candidate_name="${candidate_parent##*/}"
  valid_absolute_path "$candidate" \
    && canonical_existing_path "$candidate" \
    && [ "$candidate_leaf" = ready ] \
    && [ "$candidate" = "$candidate_parent/ready" ] \
    && [[ "$candidate_name" =~ ^session[.][A-Za-z0-9]{8}$ ]] \
    && [ "$candidate_parent" = "$state_dir/$candidate_name" ] \
    && [ -d "$candidate_parent" ] \
    && [ ! -L "$candidate_parent" ] || return 1
  canonical_state="$(@READLINK@ -f "$state_dir" 2>/dev/null || true)"
  canonical_parent="$(@READLINK@ -f "$candidate_parent" 2>/dev/null || true)"
  [ -n "$canonical_state" ] \
    && [ "$canonical_parent" = "$canonical_state/$candidate_name" ] || return 1
  session_dir="$candidate_parent"
}

watch_scope() {
  scope="$1" ready="$2"
  valid_scope_unit "$scope" || return 1
  valid_session_ready "$ready" || return 1
  cleanup_session_dir() {
    # Revalidate before every destructive operation: a hostile same-user
    # replacement becomes a harmless retained directory, never an unlink.
    valid_session_ready "$ready" || return 0
    @COREUTILS@/bin/rm -f "$session_dir/ready" "$session_dir/consumed" "$session_dir/started" "$session_dir/completed"
    @COREUTILS@/bin/rmdir "$session_dir" 2>/dev/null || true
  }
  validate_mutation_paths
  exec 9>"$lock_file"
  @FLOCK@ -s 9
  # A fresh directory is created by the launcher; remove no caller-selected
  # path and only publish readiness after this exact scope exists.
  attempts=0
  while :; do
    active="$("$systemctl" --user show "$scope" --property=ActiveState --value 2>/dev/null || true)"
    completed="$(@COREUTILS@/bin/cat "$session_dir/completed" 2>/dev/null || true)"
    [ -z "$completed" ] || [ "$completed" = 0 ] || { cleanup_session_dir; return 1; }
    if [ "$completed" = 0 ]; then
      break
    fi
    case "$active" in
      active|activating|reloading) break ;;
      inactive|failed|deactivating)
        attempts=$((attempts + 1))
        [ "$attempts" -lt 100 ] || { cleanup_session_dir; return 1; }
        @SLEEP@ 0.05
        ;;
      *)
        attempts=$((attempts + 1))
        [ "$attempts" -lt 100 ] || { cleanup_session_dir; return 1; }
        @SLEEP@ 0.05
        ;;
    esac
  done
  ready_tmp="$ready.tmp.$$"
  printf 'ready\n' > "$ready_tmp"
  @COREUTILS@/bin/mv -f "$ready_tmp" "$ready"
  while :; do
    active="$("$systemctl" --user show "$scope" --property=ActiveState --value 2>/dev/null || true)"
    case "$active" in
      active|activating|reloading) @SLEEP@ 0.2 ;;
      inactive|failed|deactivating|*) break ;;
    esac
  done
  # READY must survive a fast CLI/single-instance exit until the launching
  # wrapper acknowledges it. Otherwise a scope that terminates between the
  # write and the wrapper's next probe causes a false five-second failure.
  attempts=0
  while [ ! -e "$session_dir/consumed" ]; do
    attempts=$((attempts + 1))
    [ "$attempts" -lt 100 ] || { cleanup_session_dir; return 0; }
    @SLEEP@ 0.05
  done
  cleanup_session_dir
}

reconcile() {
  lock_ready=0
  if [ "${CRIOMOS_VSCODIUM_LOCK_HELD:-0}" = 1 ]; then
    # Keep the caller's FD 9 intact. In particular activation_refresh holds EX
    # on this descriptor while it reconciles and refreshes the registry.
    mkdir_state
  else
    if [ "$dry" -eq 1 ]; then
      if [ -e "$lock_file" ]; then exec 9<"$lock_file"; lock_ready=1; fi
    else
      mkdir_state; exec 9>"$lock_file"
    fi
    if [ "$dry" -eq 0 ] || [ "$lock_ready" -eq 1 ]; then
      # Activation must never wait behind a running GUI's shared lease. A
      # later activation can reconcile after the lease is gone.
      @FLOCK@ -xn 9 || return 0
    fi
  fi
  managed_extension || return 0
  mkdir_state
  if [ ! -e "$manifest" ]; then
    # Legacy migration is conservative: do not touch discovery while any
    # Codium process may have the old extension loaded.
    if [ -n "${USER:-}" ] && @PGREP@ -u "$USER" -f '(^|/)(codium|codium-server|VSCodium)( |$)' >/dev/null 2>&1; then
      exit 0
    fi
    found_legacy=0; exact_count=0; exact_name=""
    for candidate in "$ext_dir"/anthropic.claude-code-*-linux-x64; do
      [ -L "$candidate" ] || continue
      raw=$(@READLINK@ "$candidate" 2>/dev/null || true)
      resolved=$(@READLINK@ -f "$candidate" 2>/dev/null || true)
      [ "$raw" = "$managed" ] && [ "$resolved" = "$target" ] || continue
      exact_count=$((exact_count + 1)); exact_name="$candidate"
    done
    [ "$exact_count" -le 1 ] || { exit 0; }
    for candidate in "$ext_dir"/anthropic.claude-code-*-linux-x64; do
      [ -L "$candidate" ] || continue
      raw=$(@READLINK@ "$candidate" 2>/dev/null || true)
      resolved=$(@READLINK@ -f "$candidate" 2>/dev/null || true)
      if [ "$raw" = "$managed" ] && [ "$resolved" = "$target" ] && [ "$candidate" = "$exact_name" ]; then
        found_legacy=1
        name=${candidate##*/}
        [ "$dry" -eq 1 ] || { @COREUTILS@/bin/ln -s "$target" "$candidate.tmp.$$"; @COREUTILS@/bin/mv -Tf "$candidate.tmp.$$" "$candidate"; }
      else
        exit 0
      fi
    done
    [ "$dry" -eq 1 ] && exit 0
    if [ "$found_legacy" -eq 1 ]; then
      register_root "$root_dir/$desired" "$target"
    fi
    tmp_manifest="$manifest.tmp.$$"
    { printf 'v1-bootstrap\n'; [ "$found_legacy" -eq 1 ] && printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
    @COREUTILS@/bin/mv -f "$tmp_manifest" "$manifest"
    [ "$found_legacy" -eq 1 ] || exit 0
    exit 0
  fi
  [ "$bootstrap_only" -eq 1 ] && exit 0
  if [ -e "$manifest" ]; then
    # Do not create, retarget, or remove anything from an untrusted manifest.
    manifest_is_valid || return 0
    if [ "$manifest_header" = v1-bootstrap ]; then
      [ "$dry" -eq 1 ] && return 0
      @SED@ '1s/.*/v1-ready/' "$manifest" > "$manifest.tmp.$$"
      @COREUTILS@/bin/mv -f "$manifest.tmp.$$" "$manifest"
      return 0
    fi
  fi
  link="$ext_dir/$desired"; owned_current=0
  if [ -f "$manifest" ] && @COREUTILS@/bin/head -n1 "$manifest" | @GREP@ -Eq '^(v1|v1-ready)$'; then
    @GREP@ -Fq "	$desired	" "$manifest" && owned_current=1
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ "$owned_current" -eq 1 ] && [ -L "$link" ] && [ "$dry" -eq 0 ]; then
      [ "$(@READLINK@ -f "$link" 2>/dev/null || true)" = "$target" ] || { @COREUTILS@/bin/ln -s "$target" "$link.tmp.$$"; @COREUTILS@/bin/mv -Tf "$link.tmp.$$" "$link"; }
    elif [ ! -L "$link" ] || [ "$(@READLINK@ -f "$link" 2>/dev/null || true)" != "$target" ]; then
      printf 'criomos-codium: preserving unmanaged collision %s\n' "$link" >&2; return 0
    fi
  else
    mutate @COREUTILS@/bin/ln -s "$target" "$link.tmp.$$"; mutate @COREUTILS@/bin/mv -Tf "$link.tmp.$$" "$link"
  fi
  root="$root_dir/$desired"
  register_root "$root" "$target"
  old_lines=""; [ -f "$manifest" ] && old_lines=$(@COREUTILS@/bin/tail -n +2 "$manifest" || true)
  if [ "$dry" -eq 1 ]; then printf '+ atomic manifest update\n'; return 0; fi
  tmp_manifest="$manifest.tmp.$$"
  { printf 'v1\n'; printf '%s\n' "$old_lines" | @AWK@ -F '\t' -v d="$desired" '$3 != d && NF >= 3'; printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
  @COREUTILS@/bin/mv -f "$tmp_manifest" "$manifest"
  manifest_is_valid || return 0
  while IFS='	' read -r owner ver name tgt extra; do
    [ -z "$extra" ] && valid_manifest_entry "$owner" "$ver" "$name" "$tgt" && [ "$name" != "$desired" ] || continue
    [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] || continue
    [ -L "$root_dir/$name" ] && root_retains_target "$root_dir/$name" "$tgt" || continue
    @COREUTILS@/bin/rm -f "$ext_dir/$name" "$root_dir/$name"
  done < <(@COREUTILS@/bin/tail -n +2 "$manifest")
}

case "${1:-}" in
  --activation-refresh) activation_refresh ;;
  --prepare-launch) prepare_launch ;;
  --refresh-registry) refresh_registry ;;
  --watch-scope) watch_scope "${2:-}" "${3:-}" ;;
  --dry-run|--activate|--launch|*) reconcile "$@" ;;
esac
