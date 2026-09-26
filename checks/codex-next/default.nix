{ pkgs, inputs, ... }:
let
  user = {
    name = "next-test";
    size = "Min";
  };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = { inherit user; };
      modules = [
        ../../modules/home/profiles/min/codex-next.nix
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
assert service.Service.Environment == [ "CODEX_HOME=/home/next-test/.codex-next" ];
assert service.Service.LimitNOFILE == 524288;
assert service.Service.UMask == "0077";
assert !(configuration.systemd.user.services ? codex-remote-control);
assert
  builtins.head service.Service.ExecStart
  == "${package}/bin/codex app-server --remote-control --listen unix:///home/next-test/.codex-next/app-server-control/app-server-control.sock";
pkgs.runCommand "codex-next-contract" { } ''
  ${package}/bin/codex --version > "$out"
  test "$(cat "$out")" = "codex-cli 0.158.0-alpha.9"
  test -x ${package}/bin/codex-code-mode-host
''
