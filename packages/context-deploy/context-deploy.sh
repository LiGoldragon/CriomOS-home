# context-deploy 'Deploy.{ Repository Commit }'
#
# Deploys one landing of a context repository: the Flow Nexus runs it for
# every landing it records. The landing's commit reaches the repository's
# origin main (fast-forward only), is pinned as psyche-context in
# CriomOS-home main, that Home is pinned in CriomOS main, and the host
# deploy declared for this node is submitted through Lojix and followed to
# its terminal record, the two flake files of each held through orchestrate
# meanwhile. A node with no host deploy declared refuses before anything is
# pinned. It prints Deployed.{ Commit Home CriomOS } or
# DeployRefused.«reason» and exits non-zero. Its claim is not the witness:
# the Flow Nexus witnesses the deploy by Curriculum serving the commit.
request="${1:-}"
pattern='^Deploy\.\{ ([^ ]+) ([0-9a-f]{40}) \}$'
refuse() {
  printf 'DeployRefused.«%s»\n' "$1"
  exit 1
}
[[ "$request" =~ $pattern ]] || refuse "the request is not Deploy.{ Repository Commit }"
repository="${BASH_REMATCH[1]}"
commit="${BASH_REMATCH[2]}"
short="${commit:0:7}"
host_request='@HOST_DEPLOY@'
[ -n "$host_request" ] ||
  refuse "no host deploy request is declared for this node (criomosHome.flow.landingDeployRequest); nothing was pinned"

# The pins are the same files other flows edit in their checkouts: they are
# held through orchestrate for the whole deploy, and a held file refuses it.
lock=$(orchestrate "Lock.{ ContextDeploy$short flow-nexus [ @LOCKED_PATHS@ ] «pin and deploy the landing $short» }" 2>&1)
lock_id=$(printf '%s\n' "$lock" | sed -nE 's/^Locked\.\{ ([0-9]+) .*/\1/p')
[ -n "$lock_id" ] || refuse "the Home and CriomOS pins are held: $lock"
work=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/context-deploy.XXXXXX")
trap 'rm -rf "$work"; orchestrate "Release.$lock_id" >/dev/null 2>&1 || true' EXIT

# The landing reaches its origin; a landing nobody pushed is pushed, only
# when that fast-forwards origin main.
git -C "$repository" fetch -q origin main ||
  refuse "the context repository's origin cannot be read"
if ! git -C "$repository" merge-base --is-ancestor "$commit" origin/main; then
  git -C "$repository" push -q origin "$commit:refs/heads/main" ||
    refuse "$short is not on origin main of the context repository and does not fast-forward it"
fi

# pin URL PREFIX REVISION NAME: the repository at URL, its one flake input
# PREFIX<revision> set to REVISION on main and pushed. Prints main's commit.
pin() {
  local url="$1" prefix="$2" revision="$3" name="$4" directory="$work/$4"
  local attempt count
  for attempt in 1 2 3; do
    rm -rf "$directory"
    jj git clone --colocate "$url" "$directory" >&2 || return 1
    count=$(grep -cE "${prefix}[0-9a-f]{40}" "$directory/flake.nix" || true)
    if [ "$count" != 1 ]; then
      echo "$name flake.nix names ${prefix} $count times, not once" >&2
      return 1
    fi
    if grep -qF "${prefix}${revision}" "$directory/flake.nix"; then
      git -C "$directory" rev-parse HEAD
      return 0
    fi
    sed -i -E "s#(${prefix})[0-9a-f]{40}#\\1${revision}#" "$directory/flake.nix"
    (cd "$directory" && nix flake lock) >&2 || return 1
    (cd "$directory" &&
      jj commit -m "Pin ${prefix#github:LiGoldragon/}${revision:0:7}: a landing the approval pipeline deploys" &&
      jj bookmark set main -r @- &&
      jj git push --bookmark main) >&2 &&
      {
        git -C "$directory" rev-parse main
        return 0
      }
    echo "$name main moved while pinning (attempt $attempt)" >&2
  done
  return 1
}

home=$(pin "@HOME_URL@" "github:LiGoldragon/psyche-context/" "$commit" CriomOS-home) ||
  refuse "psyche-context $short could not be pinned in CriomOS-home main"
system=$(pin "@SYSTEM_URL@" "github:LiGoldragon/CriomOS-home/" "$home" CriomOS) ||
  refuse "CriomOS-home ${home:0:8} could not be pinned in CriomOS main"

host_request="${host_request//@CRIOMOS_REVISION@/$system}"
export LOJIX_OWNER_SOCKET="${LOJIX_OWNER_SOCKET:-/run/lojix/meta.sock}"
accepted=$(lojix-meta "$host_request" 2>&1) ||
  refuse "the host deploy of CriomOS ${system:0:8} was not submitted: $accepted"
deployment=$(printf '%s\n' "$accepted" | sed -nE 's/^DeployAccepted\.\{ ([0-9]+) .*/\1/p')
[ -n "$deployment" ] ||
  refuse "the host deploy of CriomOS ${system:0:8} was not accepted: $accepted"
terminal=""
while IFS= read -r line; do
  case "$line" in
  *Some.Succeeded*)
    terminal=Succeeded
    break
    ;;
  *Some.Failed* | *Some.Rejected*)
    terminal="$line"
    break
    ;;
  esac
done < <(lojix "WatchDeployments.{ Some.$deployment None None }" 2>&1)
[ "$terminal" = Succeeded ] ||
  refuse "host deploy $deployment of CriomOS ${system:0:8} ended: ${terminal:-the watch closed without a terminal record}"
printf 'Deployed.{ %s %s %s }\n' "$commit" "$home" "$system"
