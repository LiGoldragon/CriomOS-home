# Regenerates the Primary workspace skill directories from the main of
# psyche-belief, mind-belief and field-belief as it stands now.
# Each repository is fetched from origin main; the newer of local main and
# the fetched main is read straight from git objects, never from a working
# tree. Environment: PRIMARY (workspace), GENERATOR (generate.clj).
primary="${PRIMARY:-$HOME/primary}"
generator="${GENERATOR:?GENERATOR is the path of generate.clj}"
surfaces=".claude/skills .agents/skills .codex/skills .pi/skills .opencode/skills"

exec 9>"${XDG_RUNTIME_DIR:-/tmp}/context-skills.lock"
flock 9

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

sources=()
for name in psyche-belief mind-belief field-belief; do
  repo="$primary/repos/$name"
  git -C "$repo" fetch --quiet origin main || echo "fetch failed for $name; using local main" >&2
  revision="$(git -C "$repo" rev-parse --verify refs/heads/main)"
  if remote="$(git -C "$repo" rev-parse --verify --quiet refs/remotes/origin/main)" \
    && git -C "$repo" merge-base --is-ancestor "$revision" "$remote"; then
    revision="$remote"
  fi
  mkdir "$work/$name"
  git -C "$repo" archive "$revision" | tar -x -C "$work/$name"
  sources+=("$work/$name=$revision")
done

bb "$generator" "$work/out" "${sources[@]}"

for surface in $surfaces; do
  target="$primary/$surface"
  if [ -L "$target" ]; then rm "$target"; fi
  mkdir -p "$target"
  rsync -a --delete --delay-updates "$work/out/$surface/" "$target/"
done
echo "regenerated $(wc -l < "$work/out/modules") skills: ${sources[*]##*=}"
