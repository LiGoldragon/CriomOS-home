# Flow Nexus 0.51.2 is retired: no unit runs it, so nothing starts or
# restarts it at login or after a failure. Its package stays in this
# generation under its versioned client names, so the 0.51.2 artifact and
# its store at ~/.local/state/flow-0511 remain for an operator to read.
# The bare flow and flow-meta names are not declared while no Flow runs.
{ config, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.51.2";
      slug = "0511";
    })
  ];

  criomosHome.flow0511.enable = false;

  home.packages = [ config.criomosHome.flow0511.clients ];
}
