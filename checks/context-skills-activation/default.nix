{ pkgs, ... }:

let
  inherit (pkgs) lib;
  homeDirectory = "/build/context-skills-home";
  moduleResult = import ../../modules/home/profiles/min/context-skills.nix {
    inherit lib pkgs;
    config = {
      home.homeDirectory = homeDirectory;
      criomosHome.contextSkills.enable = true;
    };
  };
  moduleConfiguration =
    if moduleResult ? config && moduleResult.config ? content then
      moduleResult.config.content
    else if moduleResult ? content then
      moduleResult.content
    else
      moduleResult;
  service = moduleConfiguration.systemd.user.services.context-skills;
  path = moduleConfiguration.systemd.user.paths.context-skills;
  regenerate = pkgs.callPackage ../../packages/context-skills { };
  refs = map (name: "${homeDirectory}/primary/repos/${name}/.git/refs") [
    "psyche-belief"
    "mind-belief"
    "field-belief"
  ];
  expectedPaths = lib.concatMap (repositoryRefs: [
    "${repositoryRefs}/heads/main"
    "${repositoryRefs}/remotes/origin/main"
  ]) refs;
  assertions = [
    {
      condition = service.Service.Type == "oneshot";
      message = "Context skills generation must remain one oneshot effect.";
    }
    {
      condition = service.Service.ExecStart == "${regenerate}/bin/context-skills-regenerate";
      message = "The activation event must run the package-bound current generator.";
    }
    {
      condition = service.Install.WantedBy == [ "default.target" ];
      message = "An active Home generation must announce generation through default.target.";
    }
    {
      condition = !(service.Service ? RemainAfterExit);
      message = "The oneshot must return inactive so later ref events can run it again.";
    }
    {
      condition = path.Install.WantedBy == [ "default.target" ];
      message = "The context ref watcher must remain enabled.";
    }
    {
      condition = path.Path.Unit == "context-skills.service";
      message = "Context ref changes must invoke the same generation effect.";
    }
    {
      condition = path.Path.PathChanged == expectedPaths;
      message = "Every local and remote main ref must remain an input event.";
    }
  ];
  failures = builtins.filter (assertion: !assertion.condition) assertions;
in
if failures != [ ] then
  throw (lib.concatMapStringsSep "\n" (assertion: assertion.message) failures)
else
  pkgs.runCommand "context-skills-activation" { } ''
    test -x ${regenerate}/bin/context-skills-regenerate
    touch "$out"
  ''
