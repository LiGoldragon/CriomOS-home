{ pkgs, ... }:
let
  contextDeploy = pkgs.callPackage ../../packages/context-deploy { };
in
# The deploy's own refusals print one DeployRefused datom and exit non-zero,
# before anything is locked, cloned, pinned or deployed: a request that is
# not Deploy.{ Repository Commit }, and a node with no host deploy declared.
pkgs.runCommand "context-deploy" { } ''
  set -u
  status=0
  ${contextDeploy}/bin/context-deploy 'Deploy.{ /nowhere short }' > malformed || status=$?
  test "$status" -ne 0
  grep -Fx 'DeployRefused.«the request is not Deploy.{ Repository Commit }»' malformed
  status=0
  ${contextDeploy}/bin/context-deploy 'Deploy.{ /nowhere 2d9fbb6d7dc45dfe60e1109607baf95bec28cfa1 }' > unarmed || status=$?
  test "$status" -ne 0
  grep -Fx 'DeployRefused.«no host deploy request is declared for this node (criomosHome.flow.landingDeployRequest); nothing was pinned»' unarmed
  grep -Fq 'jj --quiet git clone' ${../../packages/context-deploy/context-deploy.sh}
  grep -Fq 'Query.ByDeployment.{ $deployment }' ${../../packages/context-deploy/context-deploy.sh}
  ! grep -Fq 'WatchDeployments' ${../../packages/context-deploy/context-deploy.sh}
  mkdir -p "$out"
  cp malformed unarmed "$out/"
''
