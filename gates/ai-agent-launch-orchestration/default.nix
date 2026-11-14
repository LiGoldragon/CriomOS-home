{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lib = pkgs.lib;
  codexCliPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  claudeCodePackage = pkgs.callPackage ../../owned-agents/claude-code { inherit inputs; };
  fixtureUser = {
    useColemak = false;
    hasPublicKey = false;
    publicKeys = [ ];
    gitSigningKey = null;
    matrixId = null;
    size = "Min";
    capabilities = [ "StableCodex" ];
    isMultimediaDev = false;
    emailAddress = "ai-agent-launch-check@example.invalid";
    githubId = "ai-agent-launch-check";
    name = "AI agent launch check";
  };
  configuration = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {
      inherit inputs;
      user = fixtureUser;
      criomos-lib = inputs.criomos-lib.lib;
      horizon = import ../../fixtures/horizon.nix;
      hexis = inputs.hexis.packages.${system}.default;
      rustToolchain = pkgs.rustc;
    };
    modules = [
      ../../modules/home/core-packages.nix
      ../../modules/home/profiles/min/default.nix
      ../../modules/home/profiles/min/remote-build-command-guard.nix
      ../../modules/home/profiles/min/codex-remote-control.nix
      {
        home = {
          username = "ai-agent-launch-check";
          homeDirectory = "/tmp/ai-agent-launch-check";
          stateVersion = "26.05";
        };
        xdg.configHome = "/tmp/ai-agent-launch-check/.config";
        stylix.polarity = "dark";
        criomos.corePackages = {
          codex = codexCliPackage;
          codexServer = codexCliPackage;
          codexNextServer = codexCliPackage;
          claude = claudeCodePackage;
          flowId = pkgs.hello;
        };
      }
    ];
  };
  profile = configuration.config;
  packageName = package: package.pname or (package.name or "");
  hasPackage = name: builtins.any (package: packageName package == name) profile.home.packages;
  codexMerge = profile.home.activation.mergeCodexConfig.data;
  codexActivation = pkgs.writeShellScript "ai-agent-launch-codex-activation" ''
    set -eu
    DRY_RUN_CMD=""
    run() {
      "$@"
    }
    ${codexMerge}
  '';
  roleFile =
    name:
    pkgs.writeText "ai-agent-launch-${name}.toml" profile.home.file.".codex/agents/${name}.toml".text;
in
assert profile.home.activation ? mergeCodexConfig;
assert builtins.elem codexCliPackage profile.home.packages;
assert !hasPackage "direct-codex";
assert !hasPackage "pi";
assert !hasPackage "direct-pi";
assert !hasPackage "pi-testing";
pkgs.runCommand "ai-agent-launch-orchestration"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.yq-go
    ];
  }
  ''
    set -eu

    codexHome="$TMPDIR/codex-home"
    mkdir -p "$codexHome/.codex"
    cat > "$codexHome/.codex/config.toml" <<'EOF'
    model = "obsolete-root-model"
    model_reasoning_effort = "low"
    unrelated_setting = "preserve-me"

    [agents]
    default_subagent_model = "obsolete-child-model"
    default_subagent_reasoning_effort = "low"
    EOF

    HOME="$codexHome" ${codexActivation}

    # yq's TOML parser rejects malformed TOML, so parsing each managed output
    # is a strict syntax witness in addition to the value assertions below.
    ${pkgs.yq-go}/bin/yq -p toml -o json -e '.' "$codexHome/.codex/config.toml" > /dev/null
    ${pkgs.yq-go}/bin/yq -p toml -o json -e '.' ${roleFile "default"} > /dev/null
    ${pkgs.yq-go}/bin/yq -p toml -o json -e '.' ${roleFile "worker"} > /dev/null
    ${pkgs.yq-go}/bin/yq -p toml -o json -e '.' ${roleFile "explorer"} > /dev/null

    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' "$codexHome/.codex/config.toml" )" = "gpt-6-astra"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' "$codexHome/.codex/config.toml" )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.agents.default_subagent_model' "$codexHome/.codex/config.toml" )" = "gpt-5.6-luna"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.agents.default_subagent_reasoning_effort' "$codexHome/.codex/config.toml" )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.approval_policy' "$codexHome/.codex/config.toml" )" = "never"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.sandbox_mode' "$codexHome/.codex/config.toml" )" = "danger-full-access"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.unrelated_setting' "$codexHome/.codex/config.toml" )" = "preserve-me"

    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "default"} )" = "gpt-5.6-luna"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "default"} )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "explorer"} )" = "gpt-5.6-luna"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "explorer"} )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "worker"} )" = "gpt-5.6-terra"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "worker"} )" = "high"

    touch "$out"
  ''
