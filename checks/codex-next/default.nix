{ pkgs, inputs, ... }:
let
  user = {
    name = "next-test";
    size = "Min";
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit inputs user; };
      modules = [
        ../../modules/home/profiles/min/codex-next.nix
        ../../modules/home/profiles/min/codex-next-candidate.nix
        {
          home.username = user.name;
          home.homeDirectory = "/home/${user.name}";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  service = configuration.systemd.user.services.codex-remote-control-next;
  package = pkgs.callPackage ../../owned-agents/codex-next { };
in
assert pkgs.lib.hasInfix "--file \"/home/next-test/.codex-next-${configuration.criomosHome.codexNextCandidate.hash}/config.toml\""
  configuration.home.activation.mergeCodexNextCandidatePermissionDefaults.data;
assert service.Service.Environment == [ "CODEX_HOME=/home/next-test/.codex-next" ];
assert service.Service.LimitNOFILE == 524288;
assert service.Unit.Conflicts == [ "codex-remote-control-next-recovery.service" ];
assert service.Unit.After == [ "codex-remote-control-next-recovery.service" ];
assert service.Unit.StartLimitIntervalSec == 60;
assert service.Unit.StartLimitBurst == 5;
assert service.Service.Restart == "on-failure";
assert service.Service.UMask == "0077";
assert !(configuration.systemd.user.services ? codex-remote-control);
assert
  builtins.head service.Service.ExecStart
  == "${package}/bin/codex app-server --remote-control --listen unix:///home/next-test/.codex-next/app-server-control/app-server-control.sock";
pkgs.runCommand "codex-next-contract" { } ''
  declared="$(grep -o '/nix/store/[^ ]*hexis-declared.json' <<'DECLARED'
${configuration.home.activation.mergeCodexNextCandidatePermissionDefaults.data}
DECLARED
)"
  ${pkgs.jq}/bin/jq -e '.approval_policy == "never" and .sandbox_mode == "danger-full-access"' "$declared"
  ${package}/bin/codex --version > "$out"
  test "$(cat "$out")" = "codex-cli 0.158.0-alpha.9"
  test -n "${configuration.criomosHome.codexNextCandidate.hash}"
  test -x ${configuration.criomosHome.codexNextCandidate.remoteClientPackage}/bin/codex-next
  test -x ${package}/bin/codex-code-mode-host
''
