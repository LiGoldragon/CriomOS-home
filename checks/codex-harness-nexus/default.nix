{ inputs, pkgs, ... }:
let
  fixtureUser = {
    name = "codex-harness-fixture";
    size = "Min";
    capabilities = [ "AgentStack" ];
  };
  fixtureHome = "/home/${fixtureUser.name}";
  codexHome = "${fixtureHome}/codex";
  configuration = user: extra: (inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = { inherit user inputs; };
    modules = [
      ../../modules/home/profiles/min/nexus-places.nix
      ../../modules/home/profiles/min/codex-harness-nexus.nix
      ({ lib, ... }: {
        options.criomosHome.codexPlain = {
          enable = lib.mkOption { type = lib.types.bool; default = true; };
          homeDirectory = lib.mkOption { type = lib.types.str; default = codexHome; };
        };
        config.home = {
          username = user.name;
          homeDirectory = fixtureHome;
          stateVersion = "26.05";
        };
      })
      extra
    ];
  }).config;
  enabled = configuration fixtureUser {};
  disabled = configuration (fixtureUser // { capabilities = []; }) {};
  custom = configuration fixtureUser {
    criomosHome.nexusPlaces.places = [ "trial" ];
    criomosHome.codexHarness = {
      place = "trial";
      rowCount = 32;
      restartDelay = "4s";
      startupTimeout = "15s";
      hookHome = null;
    };
  };
  nexus = enabled.systemd.user.services.codex-harness-nexus-040;
  translator = enabled.systemd.user.services.codex-harness-translator-040;
  configured = custom.systemd.user.services.codex-harness-translator-040;
  plan = pkgs.writeText "codex-harness-fixture-plan.json" (builtins.toJSON {
    inherit (nexus.Unit) Wants After;
    nexus = nexus.Service;
    translator = translator.Service;
    config = enabled.xdg.configFile."nexus/codex-harness-nexus.datom".text;
    hook = enabled.home.file.".local/bin/codex-harness-report".source;
    inherit codexHome;
  });
in
assert !(disabled.systemd.user.services ? codex-harness-nexus-040);
assert !(disabled.systemd.user.services ? codex-harness-translator-040);
assert nexus.Unit.Wants == [ "codex-harness-translator-040.service" ];
assert nexus.Unit.After == [ "systemd-tmpfiles-setup.service" ];
assert translator.Unit.After == [ "codex-harness-nexus-040.service" ];
assert translator.Unit.BindsTo == [ "codex-harness-nexus-040.service" ];
assert translator.Unit.PartOf == [ "codex-harness-nexus-040.service" ];
assert nexus.Service.UMask == "0077" && translator.Service.UMask == "0077";
assert translator.Service.Restart == "on-failure";
assert configured.Service.RestartSec == "4s";
assert configured.Service.TimeoutStartSec == "15s";
assert custom.xdg.configFile."nexus/codex-harness-nexus.datom".text == "{ trial }\n";
assert !(custom.home.file ? ".local/bin/codex-harness-report");
pkgs.runCommand "codex-harness-deployment-contract" {
  nativeBuildInputs = [ pkgs.python3 pkgs.jq ];
} ''
  python3 ${./replay.py} ${plan}
  merge() {
    jq -e --arg marker '/.local/bin/codex-harness-report' \
      --arg command '/home/fixture/.local/bin/codex-harness-report' --argjson timeout 5 \
      --argjson events '["SessionStart","PostToolUse"]' \
      -f ${../../packages/codex-harness-deployment/merge-hooks.jq}
  }
  merge > hooks.json <<'FIXTURE'
  {
    "unknown": true,
    "hooks": {
      "SessionStart": [{"matcher":"startup","hooks":[
        {"type":"command","command":"herdr session"},
        {"type":"command","command":"/old/.local/bin/codex-harness-report"}
      ]}],
      "PostCompact":[{"hooks":[{"type":"command","command":"/old/.local/bin/codex-harness-report"}]}],
      "Stop":[{"hooks":[{"type":"command","command":"foreign"}]}]
    }
  }
  FIXTURE
  merge < hooks.json > again.json
  cmp hooks.json again.json
  jq -e '
    .unknown and
    .hooks.SessionStart[0] == {matcher: "startup", hooks: [{type: "command", command: "herdr session"}]} and
    (.hooks.SessionStart | length) == 2 and
    .hooks.PostCompact == [] and
    .hooks.Stop == [{hooks: [{type: "command", command: "foreign"}]}] and
    .hooks.PostToolUse[0].hooks[0].timeout == 5
  ' hooks.json
  touch "$out"
''
