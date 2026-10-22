# The deployed Flow 0.38 declaration has exactly three positions.
{ pkgs, ... }:
pkgs.runCommand "flow-metaflow-tools" { nativeBuildInputs = [ pkgs.babashka pkgs.gnugrep ]; } ''
  mkdir -p config/metaflow
  for aspect in psyche mind field; do
    echo '{:modules {:system [:default-system] :user [:default-user]}}' > config/$aspect.edn
  done
  echo '{:aspect :Mind :topic :testCase :layer :Secondary :modules [:own-system]}' > config/metaflow/test.edn
  bb ${../../packages/flow-deployment/metaflows.clj} config > actual
  grep -Fx 'Configure.Metaflows.[ { { Mind testCase Secondary } [ default-system own-system ] [ default-user ] } ]' actual
  touch "$out"
''
