# Flow Nexus 0.53.0 is retired: no unit runs it, so nothing starts or
# restarts it at login or after a failure. Its package stays in this
# generation under its versioned client names, so the 0.53.0 artifact and
# its store at ~/.local/state/flow-0530 remain for an operator to read.
# The bare flow and flow-meta names point at 0.53.1.
{ config, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.53.0";
      slug = "0530";
    })
  ];

  criomosHome.flow0530 = {
    enable = false;
    declarationPath = "${config.home.homeDirectory}/.local/state/flow-declarations/metaflows-0530.datom";
    configurationDirectory = ./flow-nexus-config-0530;
    messageNexus = null;
  };

  home.packages = [ config.criomosHome.flow0530.clients ];
}
