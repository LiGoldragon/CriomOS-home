#!/usr/bin/env bash
set -euf
export LC_ALL=C

ext_dir="${CRIOMOS_VSCODIUM_EXTENSIONS_DIR:-$HOME/.vscode-oss/extensions}"
state_dir="${CRIOMOS_VSCODIUM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/criomos/vscodium-claude}"
# Nix records an automatic GC root for each --add-root user path. Keep that
# path in the user's state directory: activation never creates anything in
# /nix, while the daemon retains the target through its automatic-root tree.
root_dir="${CRIOMOS_VSCODIUM_GCROOT_DIR:-$state_dir/gcroots}"
lock_file="${CRIOMOS_VSCODIUM_LOCK_FILE:-$state_dir/lifecycle.lock}"
manifest="$state_dir/manifest"
dry=0
bootstrap_only=0
for arg in "$@"; do [ "$arg" = --bootstrap ] && bootstrap_only=1; done
for arg in "$@"; do [ "$arg" = --dry-run ] && dry=1; done
mutate() { if [ "$dry" -eq 1 ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
mkdir_state() { [ "$dry" -eq 1 ] || mkdir -p "$state_dir" "$root_dir"; }
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
  mutate @NIX_STORE@ --add-root "$1" --realise "$2" >/dev/null
}
root_retains_target() {
  root_target="$(@READLINK@ -f "$1" 2>/dev/null || true)"
  valid_target "$root_target" || return 1
  case "$2" in "$root_target"|"$root_target"/*) return 0;; *) return 1;; esac
}
manifest_is_valid() {
  manifest_valid=1; seen_names=""; manifest_header="$(head -n1 "$manifest" || true)"
  # Bash strings cannot retain NULs, so reject them before line parsing rather
  # than allowing the shell to silently reinterpret a byte stream.
  [ "$(wc -c < "$manifest")" = "$(tr -d '\000' < "$manifest" | wc -c)" ] || return 1
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
  done < <(tail -n +2 "$manifest")
  [ "$manifest_valid" -eq 1 ]
}

reconcile() {
  lock_ready=0
  if [ "$dry" -eq 1 ]; then
    if [ -e "$lock_file" ]; then exec 9<"$lock_file"; lock_ready=1; fi
  else
    mkdir_state; exec 9>"$lock_file"
  fi
  if { [ "$dry" -eq 0 ] || [ "$lock_ready" -eq 1 ]; } && [ "${CRIOMOS_VSCODIUM_LOCK_HELD:-0}" != 1 ]; then
    @FLOCK@ -x 9
  fi
  managed="$ext_dir/anthropic.claude-code"
  [ -d "$ext_dir" ] && [ -e "$managed/package.json" ] || exit 0
  version="$(@JQ@ -er '.version | strings' "$managed/package.json")" || exit 0
  valid_version "$version" || exit 0
  target="$(@READLINK@ -f "$managed")"; valid_target "$target" || exit 0
  desired="anthropic.claude-code-$version-linux-x64"
  valid_link_name "$desired" || exit 0
  mkdir_state
  if [ ! -e "$manifest" ]; then
    # Legacy migration is conservative: do not touch discovery while any
    # Codium process may have the old extension loaded.
    if command -v pgrep >/dev/null 2>&1 && pgrep -u "$USER" -f '(^|/)(codium|codium-server|VSCodium)( |$)' >/dev/null 2>&1; then
      exit 0
    fi
    found_legacy=0; exact_count=0; exact_name=""
    for candidate in "$ext_dir"/anthropic.claude-code-*-linux-x64; do
      [ -L "$candidate" ] || continue
      raw=$(readlink "$candidate" 2>/dev/null || true)
      resolved=$(@READLINK@ -f "$candidate" 2>/dev/null || true)
      [ "$raw" = "$managed" ] && [ "$resolved" = "$target" ] || continue
      exact_count=$((exact_count + 1)); exact_name="$candidate"
    done
    [ "$exact_count" -le 1 ] || { exit 0; }
    for candidate in "$ext_dir"/anthropic.claude-code-*-linux-x64; do
      [ -L "$candidate" ] || continue
      raw=$(readlink "$candidate" 2>/dev/null || true)
      resolved=$(@READLINK@ -f "$candidate" 2>/dev/null || true)
      if [ "$raw" = "$managed" ] && [ "$resolved" = "$target" ] && [ "$candidate" = "$exact_name" ]; then
        found_legacy=1
        name=${candidate##*/}
        [ "$dry" -eq 1 ] || { ln -s "$target" "$candidate.tmp.$$"; mv -Tf "$candidate.tmp.$$" "$candidate"; }
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
    mv -f "$tmp_manifest" "$manifest"
    [ "$found_legacy" -eq 1 ] || exit 0
    exit 0
  fi
  [ "$bootstrap_only" -eq 1 ] && exit 0
  if [ -e "$manifest" ]; then
    # Do not create, retarget, or remove anything from an untrusted manifest.
    manifest_is_valid || return 0
    if [ "$manifest_header" = v1-bootstrap ]; then
      [ "$dry" -eq 1 ] && return 0
      sed '1s/.*/v1-ready/' "$manifest" > "$manifest.tmp.$$"
      mv -f "$manifest.tmp.$$" "$manifest"
      return 0
    fi
  fi
  link="$ext_dir/$desired"; owned_current=0
  if [ -f "$manifest" ] && head -n1 "$manifest" | grep -Eq '^(v1|v1-ready)$'; then
    grep -Fq "	$desired	" "$manifest" && owned_current=1
  fi
  if [ -e "$link" ] || [ -L "$link" ]; then
    if [ "$owned_current" -eq 1 ] && [ -L "$link" ] && [ "$dry" -eq 0 ]; then
      [ "$(@READLINK@ -f "$link" 2>/dev/null || true)" = "$target" ] || { ln -s "$target" "$link.tmp.$$"; mv -Tf "$link.tmp.$$" "$link"; }
    elif [ ! -L "$link" ] || [ "$(@READLINK@ -f "$link" 2>/dev/null || true)" != "$target" ]; then
      printf 'criomos-codium: preserving unmanaged collision %s\n' "$link" >&2; return 0
    fi
  else
    mutate ln -s "$target" "$link.tmp.$$"; mutate mv -Tf "$link.tmp.$$" "$link"
  fi
  root="$root_dir/$desired"
  register_root "$root" "$target"
  old_lines=""; [ -f "$manifest" ] && old_lines=$(tail -n +2 "$manifest" || true)
  if [ "$dry" -eq 1 ]; then printf '+ atomic manifest update\n'; return 0; fi
  tmp_manifest="$manifest.tmp.$$"
  { printf 'v1\n'; printf '%s\n' "$old_lines" | awk -F '\t' -v d="$desired" '$3 != d && NF >= 3'; printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
  mv -f "$tmp_manifest" "$manifest"
  manifest_is_valid || return 0
  while IFS='	' read -r owner ver name tgt extra; do
    [ -z "$extra" ] && valid_manifest_entry "$owner" "$ver" "$name" "$tgt" && [ "$name" != "$desired" ] || continue
    [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] || continue
    [ -L "$root_dir/$name" ] && root_retains_target "$root_dir/$name" "$tgt" || continue
    rm -f "$ext_dir/$name" "$root_dir/$name"
  done < <(tail -n +2 "$manifest")
}

case "${1:-}" in --dry-run|--activate|--launch|*) reconcile "$@";; esac
