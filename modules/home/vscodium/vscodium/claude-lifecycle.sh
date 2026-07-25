#!/usr/bin/env bash
set -euf

ext_dir="${CRIOMOS_VSCODIUM_EXTENSIONS_DIR:-$HOME/.vscode-oss/extensions}"
state_dir="${CRIOMOS_VSCODIUM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/criomos/vscodium-claude}"
root_dir="${CRIOMOS_VSCODIUM_GCROOT_DIR:-/nix/var/nix/gcroots/per-user/$USER/criomos-vscodium-claude}"
lock_file="${CRIOMOS_VSCODIUM_LOCK_FILE:-$state_dir/lifecycle.lock}"
manifest="$state_dir/manifest"
dry=0
bootstrap_only=0
for arg in "$@"; do [ "$arg" = --bootstrap ] && bootstrap_only=1; done
for arg in "$@"; do [ "$arg" = --dry-run ] && dry=1; done
mutate() { if [ "$dry" -eq 1 ]; then printf '+ %s\n' "$*"; else "$@"; fi; }
mkdir_state() { [ "$dry" -eq 1 ] || mkdir -p "$state_dir" "$root_dir"; }
valid_target() { case "$1" in /nix/store/*) [ -e "$1" ];; *) return 1;; esac; }
valid_link_name() { case "$1" in anthropic.claude-code-*-linux-x64) return 0;; *) return 1;; esac; }

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
  target="$(@READLINK@ -f "$managed")"; valid_target "$target" || exit 0
  desired="anthropic.claude-code-$version-linux-x64"
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
      ln -s "$target" "$root_dir/$desired.tmp.$$"; mv -Tf "$root_dir/$desired.tmp.$$" "$root_dir/$desired"
    fi
    tmp_manifest="$manifest.tmp.$$"
    { printf 'v1-bootstrap\n'; [ "$found_legacy" -eq 1 ] && printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
    mv -f "$tmp_manifest" "$manifest"
    [ "$found_legacy" -eq 1 ] || exit 0
    exit 0
  fi
  [ "$bootstrap_only" -eq 1 ] && exit 0
  if [ -e "$manifest" ]; then
    header=$(head -n1 "$manifest" || true)
    case "$header" in v1|v1-bootstrap|v1-ready) ;; *) exit 0;; esac
    if [ "$header" = v1-bootstrap ]; then
      [ "$dry" -eq 1 ] && return 0
      sed '1s/.*/v1-ready/' "$manifest" > "$manifest.tmp.$$"
      mv -f "$manifest.tmp.$$" "$manifest"
      return 0
    fi
    [ "$header" = v1-ready ] && :
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
  if [ ! -L "$root" ] || [ "$(@READLINK@ -f "$root" 2>/dev/null || true)" != "$target" ]; then
    mutate ln -s "$target" "$root.tmp.$$"; mutate mv -Tf "$root.tmp.$$" "$root"
  fi
  old_lines=""; [ -f "$manifest" ] && old_lines=$(tail -n +2 "$manifest" || true)
  if [ "$dry" -eq 1 ]; then printf '+ atomic manifest update\n'; return 0; fi
  tmp_manifest="$manifest.tmp.$$"
  { printf 'v1\n'; printf '%s\n' "$old_lines" | awk -F '\t' -v d="$desired" '$3 != d && NF >= 3'; printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
  mv -f "$tmp_manifest" "$manifest"
  manifest_valid=1; seen_names=""
  while IFS=$'\t' read -r owner ver name tgt extra; do
    [ -z "$extra" ] && [ "$owner" = managed ] && valid_link_name "$name" && valid_target "$tgt" || { manifest_valid=0; break; }
    case " $seen_names " in *" $name "*) manifest_valid=0; break;; esac
    seen_names="$seen_names $name"
    [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] || { manifest_valid=0; break; }
    [ -L "$root_dir/$name" ] && [ "$(@READLINK@ -f "$root_dir/$name" 2>/dev/null || true)" = "$tgt" ] || { manifest_valid=0; break; }
  done < <(tail -n +2 "$manifest")
  [ "$manifest_valid" -eq 1 ] || return 0
  while IFS='	' read -r owner ver name tgt; do
    [ "$owner" = managed ] && [ "$name" != "$desired" ] || continue
    valid_link_name "$name" || continue
    [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] || continue
    [ -L "$root_dir/$name" ] && [ "$(@READLINK@ -f "$root_dir/$name" 2>/dev/null || true)" = "$tgt" ] || continue
    valid_target "$tgt" || continue
    rm -f "$ext_dir/$name" "$root_dir/$name"
  done < <(tail -n +2 "$manifest")
}

case "${1:-}" in --dry-run|--activate|--launch|*) reconcile "$@";; esac
