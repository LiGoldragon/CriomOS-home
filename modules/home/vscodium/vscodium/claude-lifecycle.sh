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
immutable="$ext_dir/.extensions-immutable.json"
registry_state="$state_dir/extensions-immutable.registry.json"
dry=0
bootstrap_only=0
nix_store="${CRIOMOS_VSCODIUM_NIX_STORE:-@NIX_STORE@}"
codium="${CRIOMOS_VSCODIUM_CODIUM:-@CODIUM@}"
for runtime_command in "$nix_store" "$codium"; do
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
  root="$1" root_target="$2"
  # Nix roots the containing store output when the extension itself is a
  # subdirectory. Accept that output root only when it retains the declared
  # extension target. Never retarget an existing, unrecognised root.
  if [ -e "$root" ] || [ -L "$root" ]; then
    [ -L "$root" ] && root_retains_target "$root" "$root_target" || return 1
  fi
  mutate "$nix_store" --add-root "$root" --realise "$root_target" >/dev/null || return 1
  [ "$dry" -eq 1 ] && return 0
  [ -L "$root" ] && root_retains_target "$root" "$root_target"
}
root_retains_target() {
  root_target="$(@READLINK@ -f "$1" 2>/dev/null || true)"
  valid_target "$root_target" || return 1
  case "$2" in "$root_target"|"$root_target"/*) return 0;; *) return 1;; esac
}
root_missing() {
  [ ! -e "$1" ] && [ ! -L "$1" ]
}
root_is_stale_managed_extension() {
  stale_root="$1"
  # A stale automatic root retains the containing extension output.  Require
  # that precise shape as well as a valid, different Claude version before
  # replacing it; an arbitrary store path at a managed-looking filename is
  # not authority to remove anything.
  stale_output="$(@READLINK@ -f "$stale_root" 2>/dev/null || true)"
  valid_target "$stale_output" || return 1
  stale_version="$(@JQ@ -er '.version | strings' "$stale_output/extension/package.json" 2>/dev/null || true)"
  valid_version "$stale_version" && [ "$stale_version" != "$version" ]
}
replace_stale_managed_root() {
  root="$1" root_target="$2"
  # Only the manifest's exact current entry is eligible.  The stable and
  # versioned Home Manager links independently prove the target is current;
  # the manifest proves this root name is lifecycle-owned.  Everything else
  # remains a fail-closed collision.
  [ "$root" = "$root_dir/$desired" ] && [ "$root_target" = "$target" ] \
    && [ -L "$ext_dir/$desired" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$desired" 2>/dev/null || true)" = "$target" ] \
    && [ -L "$root" ] && ! root_retains_target "$root" "$root_target" \
    && root_is_stale_managed_extension "$root" || return 1
  [ "$dry" -eq 0 ] || return 1

  stale_backup="$root.stale.$$"
  root_missing "$stale_backup" || return 1
  # Renaming the old link out of the declared name is atomic.  If Nix cannot
  # register the replacement, restore precisely that link before returning
  # failure, leaving manifest and registry convergence unavailable.
  @COREUTILS@/bin/mv -T "$root" "$stale_backup" || return 1
  if register_root "$root" "$root_target"; then
    @COREUTILS@/bin/rm -f "$stale_backup"
    @COREUTILS@/bin/sync -f "$root_dir"
    return 0
  fi
  if root_missing "$root"; then
    @COREUTILS@/bin/mv -T "$stale_backup" "$root" || return 1
  elif [ -L "$root" ] && root_retains_target "$root" "$root_target"; then
    @COREUTILS@/bin/rm -f "$root"
    @COREUTILS@/bin/mv -T "$stale_backup" "$root" || return 1
  else
    # An unexpected concurrent replacement is neither ours nor safe to
    # delete. Leave both paths for investigation and fail closed.
    return 1
  fi
  @COREUTILS@/bin/sync -f "$root_dir"
  return 1
}
# Older lifecycle releases wrote versioned aliases through the stable managed
# link. Preserve that narrowly owned shape long enough to migrate it after Home
# Manager moves the stable link to a newer extension target.
manifest_entry_is_owned_indirection() {
  entry_name="$1" entry_target="$2"
  [ -L "$ext_dir/$entry_name" ] \
    && [ "$(@READLINK@ "$ext_dir/$entry_name" 2>/dev/null || true)" = "$managed" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$entry_name" 2>/dev/null || true)" = "$target" ] \
    && [ -L "$root_dir/$entry_name" ] \
    && root_retains_target "$root_dir/$entry_name" "$entry_target"
}
manifest_is_valid() {
  manifest_valid=1; seen_names=""; manifest_prior_entries=""; manifest_header="$(@COREUTILS@/bin/head -n1 "$manifest" || true)"
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
    if [ -L "$ext_dir/$name" ] \
      && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] \
      && [ -L "$root_dir/$name" ] \
      && root_retains_target "$root_dir/$name" "$tgt"; then
      :
    elif manifest_entry_is_owned_indirection "$name" "$tgt"; then
      :
    else
      manifest_valid=0; break
    fi
    [ "$name" = "$desired" ] || manifest_prior_entries="$manifest_prior_entries$line"$'\n'
  done < <(@COREUTILS@/bin/tail -n +2 "$manifest")
  [ "$manifest_valid" -eq 1 ]
}

repair_missing_manifest_roots() {
  # Validate the complete manifest before mutation. A missing root next to a
  # direct, target-matching owned link is repairable. The sole existing-root
  # exception is the exact declared current root proven stale by its own
  # extension output; every other collision remains untouched.
  manifest_repair_entries=""; seen_names=""; manifest_header="$(@COREUTILS@/bin/head -n1 "$manifest" || true)"
  [ "$(@COREUTILS@/bin/wc -c < "$manifest")" = "$(@COREUTILS@/bin/tr -d '\000' < "$manifest" | @COREUTILS@/bin/wc -c)" ] || return 1
  case "$manifest_header" in v1|v1-bootstrap|v1-ready) ;; *) return 1;; esac
  while IFS= read -r line || [ -n "$line" ]; do
    tabs="${line//[^$'\t']/}"
    [ "${#tabs}" -eq 3 ] || return 1
    IFS=$'\t' read -r owner ver name tgt extra <<< "$line"
    [ -z "$extra" ] && valid_manifest_entry "$owner" "$ver" "$name" "$tgt" || return 1
    case " $seen_names " in *" $name "*) return 1;; esac
    seen_names="$seen_names $name"
    root="$root_dir/$name"
    if [ -L "$ext_dir/$name" ] && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ]; then
      if [ -L "$root" ] && root_retains_target "$root" "$tgt"; then
        :
      elif root_missing "$root"; then
        manifest_repair_entries="$manifest_repair_entries$name"$'\t'"$tgt"$'\n'
      elif replace_stale_managed_root "$root" "$tgt"; then
        :
      else
        return 1
      fi
    elif manifest_entry_is_owned_indirection "$name" "$tgt"; then
      :
    else
      return 1
    fi
  done < <(@COREUTILS@/bin/tail -n +2 "$manifest")
  while IFS=$'\t' read -r name tgt || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    register_root "$root_dir/$name" "$tgt" || return 1
  done <<< "$manifest_repair_entries"
}

cleanup_prior_manifest_entries() {
  prior_entries="$1"
  while IFS= read -r line || [ -n "$line" ]; do
    tabs="${line//[^$'\t']/}"
    [ "${#tabs}" -eq 3 ] || continue
    IFS=$'\t' read -r owner ver name tgt extra <<< "$line"
    [ -z "$extra" ] && valid_manifest_entry "$owner" "$ver" "$name" "$tgt" || continue
    [ "$name" = "$desired" ] && continue
    if [ -L "$ext_dir/$name" ] \
      && [ "$(@READLINK@ -f "$ext_dir/$name" 2>/dev/null || true)" = "$tgt" ] \
      && [ -L "$root_dir/$name" ] \
      && root_retains_target "$root_dir/$name" "$tgt"; then
      :
    elif manifest_entry_is_owned_indirection "$name" "$tgt"; then
      :
    else
      continue
    fi
    @COREUTILS@/bin/rm -f "$ext_dir/$name" "$root_dir/$name"
  done <<< "$prior_entries"
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

# The immutable declaration names the two extensions this lifecycle owns. The
# mutable registry may contain user-managed entries as well, so validate the
# two declared records and leave every other record structurally untouched.
registry_matches_immutable() {
  [ -f "$registry" ] && [ -f "$immutable" ] && @JQ@ -e \
    --arg claude_id anthropic.claude-code \
    --arg claude_version "$version" \
    --arg claude_path "$ext_dir/$desired" \
    --arg claude_relative "$desired" \
    --arg openai_id openai.chatgpt \
    --arg ext_dir "$ext_dir" \
    '. as $registry
     | input as $immutable
     | def records($items; $id): [$items[] | select(.identifier.id? == $id)];
       if ($registry | type == "array") and ($immutable | type == "array") then
         (records($registry; $claude_id)) as $registry_claude
         | (records($registry; $openai_id)) as $registry_openai
         | (records($immutable; $claude_id)) as $immutable_claude
         | (records($immutable; $openai_id)) as $immutable_openai
         | if ($registry_claude | length == 1)
              and ($registry_openai | length == 1)
              and ($immutable_claude | length == 1)
              and ($immutable_openai | length == 1)
            then
              $registry_claude[0] as $claude_current
              | $registry_openai[0] as $openai_current
              | $immutable_claude[0] as $claude
              | $immutable_openai[0] as $openai
              | ($claude.version? == $claude_version)
              and ($openai.version? | type == "string")
              and ($openai.relativeLocation? | type == "string")
              and ($openai.relativeLocation | test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
              and ($claude_current.version? == $claude_version)
              and ($claude_current.relativeLocation? == $claude_relative)
              and ($claude_current.location.path? == $claude_path)
              and ($claude_current.location.fsPath? == $claude_path)
              and ($openai_current.version? == $openai.version)
              and ($openai_current.relativeLocation? == $openai.relativeLocation)
              and ($openai_current.location.path? == ($ext_dir + "/" + $openai.relativeLocation))
              and ($openai_current.location.fsPath? == ($ext_dir + "/" + $openai.relativeLocation))
            else false
           end
       else false
       end' \
    "$registry" "$immutable" >/dev/null 2>&1
}

registry_is_current() {
  [ -f "$registry_state" ] && [ ! -L "$registry_state" ] \
    && @DIFFUTILS@/bin/cmp -s "$immutable" "$registry_state" \
    && registry_matches_immutable
}

record_registry_state() {
  registry_state_tmp="$registry_state.tmp.$$"
  @COREUTILS@/bin/cp "$immutable" "$registry_state_tmp" || {
    @COREUTILS@/bin/rm -f "$registry_state_tmp"
    return 1
  }
  @COREUTILS@/bin/sync -f "$registry_state_tmp"
  @COREUTILS@/bin/mv -f "$registry_state_tmp" "$registry_state"
  @COREUTILS@/bin/sync -f "$registry_state"
  @COREUTILS@/bin/sync -f "$state_dir"
}

transform_registry() {
  registry_tmp="$registry.tmp.$$"
  @JQ@ -e \
    --arg claude_id anthropic.claude-code \
    --arg claude_version "$version" \
    --arg claude_path "$ext_dir/$desired" \
    --arg claude_relative "$desired" \
    --arg openai_id openai.chatgpt \
    --arg ext_dir "$ext_dir" \
    '. as $registry
     | input as $immutable
     | def records($items; $id): [$items[] | select(.identifier.id? == $id)];
       if ($registry | type == "array")
          and ($immutable | type == "array")
          and (records($registry; $claude_id) | length == 1)
          and (records($registry; $openai_id) | length == 1)
          and (records($immutable; $claude_id) | length == 1)
          and (records($immutable; $openai_id) | length == 1)
        then
          (records($immutable; $claude_id)[0]) as $claude
          | (records($immutable; $openai_id)[0]) as $openai
          | if ($claude.version? == $claude_version)
               and ($openai.version? | type == "string")
               and ($openai.relativeLocation? | type == "string")
               and ($openai.relativeLocation | test("^[A-Za-z0-9][A-Za-z0-9._-]*$"))
            then map(
              if .identifier.id? == $claude_id then
                .version = $claude_version
                | .relativeLocation = $claude_relative
                | .location = ((if (.location | type == "object") then .location else {} end)
                    | .path = $claude_path | .fsPath = $claude_path)
              elif .identifier.id? == $openai_id then
                .version = $openai.version
                | .relativeLocation = $openai.relativeLocation
                | .location = ((if (.location | type == "object") then .location else {} end)
                    | .path = ($ext_dir + "/" + $openai.relativeLocation)
                    | .fsPath = ($ext_dir + "/" + $openai.relativeLocation))
              else . end
            )
            else error("invalid immutable registry target")
          end
        else error("registry targets are not unique")
       end' \
    "$registry" "$immutable" > "$registry_tmp" || {
      @COREUTILS@/bin/rm -f "$registry_tmp"
      return 1
    }
  @COREUTILS@/bin/sync -f "$registry_tmp"
  @COREUTILS@/bin/mv -f "$registry_tmp" "$registry"
  @COREUTILS@/bin/sync -f "$registry"
  @COREUTILS@/bin/sync -f "$ext_dir"
}

# Home Manager owns the immutable declaration while VSCodium owns its mutable
# discovery registry.  A first activation after a disrupted or legacy state
# may have the declaration and extension links but no mutable registry yet.
# Rebuild just the two owner records atomically, preserving every unrelated
# user record when the existing registry is a valid array.
reconcile_registry_from_immutable() {
  registry_tmp="$registry.tmp.$$"
  [ ! -e "$registry" ] && [ ! -L "$registry" ] || return 1
  # Seed the absent mutable registry from Home Manager's declaration, then
  # pass through the existing structured transform below to install the
  # mutable location fields atomically.
  @COREUTILS@/bin/cp "$immutable" "$registry_tmp" || return 1
  @COREUTILS@/bin/sync -f "$registry_tmp"
  @COREUTILS@/bin/mv -f "$registry_tmp" "$registry"
  @COREUTILS@/bin/sync -f "$registry"
  @COREUTILS@/bin/sync -f "$ext_dir"
  transform_registry
}

refresh_registry() {
  managed_extension || return 1
  [ -L "$ext_dir/$desired" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$desired" 2>/dev/null || true)" = "$target" ] || return 1
  registry_is_current && return 0

  # The declaration is authoritative.  A registry which already agrees with
  # it only needs its owner-state witness restored; a missing registry can be
  # rebuilt directly from that declaration without asking an absent prior
  # manifest to admit it.
  registry_matches_immutable && record_registry_state && return 0
  if [ ! -e "$registry" ] && [ ! -L "$registry" ]; then
    reconcile_registry_from_immutable \
      && registry_matches_immutable && record_registry_state
    return
  fi

  # Existing mutable state is potentially user-controlled.  Preserve it until
  # the supported Codium refresh and our validation both succeed, then retain
  # the resulting declaration witness.  A failed refresh is fail-closed: the
  # registry is restored unchanged and the GUI launcher will not start.
  [ -f "$registry" ] && [ ! -L "$registry" ] || return 1
  registry_backup="$(@COREUTILS@/bin/mktemp "$state_dir/registry-backup.XXXXXXXX")" || return 1
  @COREUTILS@/bin/cp "$registry" "$registry_backup" || {
    @COREUTILS@/bin/rm -f "$registry_backup"
    return 1
  }
  if CRIOMOS_VSCODIUM_REGISTRY_BACKUP="$registry_backup" "$codium" --list-extensions >/dev/null 2>&1 \
    && transform_registry && registry_matches_immutable && record_registry_state; then
    @COREUTILS@/bin/rm -f "$registry_backup"
    return 0
  fi
  @COREUTILS@/bin/cp "$registry_backup" "$registry.tmp.$$" \
    && @COREUTILS@/bin/mv -f "$registry.tmp.$$" "$registry"
  @COREUTILS@/bin/rm -f "$registry_backup" "$registry.tmp.$$"
  return 1
}

launch_ready() {
  managed_extension \
    && [ -L "$ext_dir/$desired" ] \
    && [ "$(@READLINK@ -f "$ext_dir/$desired" 2>/dev/null || true)" = "$target" ] \
    && [ -f "$manifest" ] \
    && manifest_is_valid \
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
  # A missing manifest needs the same bounded bootstrap/ready progression as
  # a launch.  Keep it in activation so a fresh owner generation is usable
  # before any GUI process is started.
  CRIOMOS_VSCODIUM_LOCK_HELD=1
  reconcile --activation-recovery
  launch_ready || reconcile --activation-recovery
  launch_ready || reconcile --activation-recovery
  launch_ready || return 0
  refresh_registry
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
    # Home Manager's current declared versioned link and the stable package
    # link are sufficient authority to reconstruct a lost manifest.  Leave
    # other versioned links alone: without the missing manifest they are not
    # evidence against the declared current target, nor authority to clean up.
    found_legacy=0
    candidate="$ext_dir/$desired"
    if [ -e "$candidate" ] || [ -L "$candidate" ]; then
      [ -L "$candidate" ] || exit 0
      raw=$(@READLINK@ "$candidate" 2>/dev/null || true)
      resolved=$(@READLINK@ -f "$candidate" 2>/dev/null || true)
      [ "$resolved" = "$target" ] || exit 0
      [ "$raw" = "$managed" ] || [ "$raw" = "$target" ] || exit 0
      found_legacy=1
      [ "$dry" -eq 1 ] || { @COREUTILS@/bin/ln -s "$target" "$candidate.tmp.$$"; @COREUTILS@/bin/mv -Tf "$candidate.tmp.$$" "$candidate"; }
    fi
    [ "$dry" -eq 1 ] && exit 0
    if [ "$found_legacy" -eq 1 ]; then
      register_root "$root_dir/$desired" "$target" || exit 0
    fi
    tmp_manifest="$manifest.tmp.$$"
    { printf 'v1-bootstrap\n'; [ "$found_legacy" -eq 1 ] && printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
    @COREUTILS@/bin/mv -f "$tmp_manifest" "$manifest"
    [ "$found_legacy" -eq 1 ] || { exit 0; }
    exit 0
  fi
  [ "$bootstrap_only" -eq 1 ] && exit 0
  if [ -e "$manifest" ]; then
    # Do not create, retarget, or remove anything from an untrusted manifest.
    repair_missing_manifest_roots || return 0
    manifest_is_valid || return 0
    if [ "$manifest_header" = v1-bootstrap ] && [ -z "$manifest_prior_entries" ]; then
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
  register_root "$root" "$target" || return 0
  prior_entries="$manifest_prior_entries"
  if [ "$dry" -eq 1 ]; then printf '+ atomic manifest update\n'; return 0; fi
  tmp_manifest="$manifest.tmp.$$"
  { printf 'v1\n'; printf 'managed\t%s\t%s\t%s\n' "$version" "$desired" "$target"; } > "$tmp_manifest"
  @COREUTILS@/bin/mv -f "$tmp_manifest" "$manifest"
  manifest_is_valid || return 0
  cleanup_prior_manifest_entries "$prior_entries"
}

case "${1:-}" in
  --activation-refresh) activation_refresh ;;
  --prepare-launch) prepare_launch ;;
  --refresh-registry) refresh_registry ;;
  --dry-run|--activate|--launch|*) reconcile "$@" ;;
esac
