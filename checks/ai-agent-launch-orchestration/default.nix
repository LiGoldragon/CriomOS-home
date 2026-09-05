{ inputs, pkgs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  lib = pkgs.lib // {
    hm.dag.entryBefore = _dependencies: data: { inherit data; };
    hm.dag.entryAfter = _dependencies: data: { inherit data; };
  };
  codexCliPackage = pkgs.callPackage ../../owned-agents/codex { inherit inputs; };
  claudeCodePackage = pkgs.callPackage ../../owned-agents/claude-code { inherit inputs; };
  fixtureUser = {
    useColemak = false;
    hasPubKey = false;
    gitSigningKey = null;
    matrixId = null;
    size.min = true;
    isMultimediaDev = false;
    emailAddress = "ai-agent-launch-check@example.invalid";
    githubId = "ai-agent-launch-check";
    name = "AI agent launch check";
  };
  moduleResult = import ../../modules/home/profiles/min/default.nix {
    inherit inputs lib pkgs;
    criomos-lib = inputs.criomos-lib.lib;
    user = fixtureUser;
    horizon.node.machine.arch = "x86-64";
    config = {
      home.homeDirectory = "/tmp/ai-agent-launch-check";
      xdg.configHome = "/tmp/ai-agent-launch-check/.config";
      stylix.polarity = "dark";
      criomos.corePackages = {
        codex = codexCliPackage;
        claude = claudeCodePackage;
        flowId = pkgs.hello;
      };
    };
    hexis = inputs.hexis.packages.${system}.default;
    rustToolchain = pkgs.rustc;
  };
  profile = moduleResult.config.content;
  packageName = package: package.pname or (package.name or "");
  hasPackage = name: builtins.any (package: packageName package == name) profile.home.packages;
  codexCleanup = profile.home.activation.removeStaleCodexConfiguration.data;
  codexMerge = profile.home.activation.mergeCodexConfig.data;
  codexActivation = pkgs.writeShellScript "ai-agent-launch-codex-activation" ''
    set -eu
    DRY_RUN_CMD=""
    run() {
      "$@"
    }
    ${codexCleanup}
    ${codexMerge}
  '';
  roleFile =
    name:
    pkgs.writeText "ai-agent-launch-${name}.toml" profile.home.file.".codex/agents/${name}.toml".text;
in
assert profile.home.activation ? removeStaleCodexConfiguration;
assert profile.home.activation ? mergeCodexConfig;
assert builtins.elem codexCliPackage profile.home.packages;
assert !hasPackage "direct-codex";
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

    [orchestrator]
    model = "obsolete-orchestrator-model"

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
    test "$( ${pkgs.yq-go}/bin/yq -p toml -o json 'has("orchestrator")' "$codexHome/.codex/config.toml" )" = false

    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "default"} )" = "gpt-5.6-luna"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "default"} )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "explorer"} )" = "gpt-5.6-luna"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "explorer"} )" = "xhigh"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model' ${roleFile "worker"} )" = "gpt-5.6-terra"
    test "$( ${pkgs.yq-go}/bin/yq -p toml '.model_reasoning_effort' ${roleFile "worker"} )" = "high"

    touch "$out"
  ''
