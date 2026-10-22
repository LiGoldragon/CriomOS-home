# The initializer preserves explicit empty tool sets and gives a simplified
# judgment only its own prompt, rather than regular flow instructions.
{ pkgs, ... }:
pkgs.runCommand "flow-metaflow-tools"
  {
    nativeBuildInputs = [ pkgs.babashka pkgs.gnugrep ];
  }
  ''
    mkdir -p config/metaflow
    for aspect in psyche mind field; do
      echo '{:modules {:system [:default-system] :user [:default-user]}}' > config/$aspect.edn
    done
    cat > config/metaflow/judgment.edn <<'EOF'
    {:aspect :Psyche :topic :judgment :layer :Primary
     :flow-kind :Simplified :tools []
     :modules [:spirit-core] :user-modules []}
    EOF
    bb ${../../packages/flow-deployment/metaflows.clj} config > simplified
    grep -Fx 'Configure.Metaflows.[ { { Psyche judgment Primary } [ spirit-core ] [  ] Simplified Explicit.[  ] } ]' simplified
    cat > config/metaflow/regular.edn <<'EOF'
    {:aspect :Mind :topic :test :layer :Secondary
     :tools [:Bash "ToolSearch"] :modules [:own-system]}
    EOF
    bb ${../../packages/flow-deployment/metaflows.clj} config 'Field investigation Secondary' > mixed
    grep -F '{ { Mind test Secondary } [ default-system own-system ] [ default-user ] Regular Explicit.[ «Bash» «ToolSearch» ] }' mixed
    grep -F '{ { Field investigation Secondary } [ default-system ] [ default-user ] Regular Default }' mixed
    sed -i 's/:tools \[\]/:tools [:Bash]/' config/metaflow/judgment.edn
    if bb ${../../packages/flow-deployment/metaflows.clj} config; then
      echo 'simplified declaration accepted regular tools' >&2
      exit 1
    fi
    touch "$out"
  ''
