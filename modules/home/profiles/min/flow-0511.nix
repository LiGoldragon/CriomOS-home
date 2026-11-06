# Flow Nexus 0.51.1 runs beside 0.51 while its authenticated seats adopt it.
{ config, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.51.1";
      slug = "0511";
    })
  ];

  # The unversioned clients move only when this Home generation activates.
  home.file.".local/bin/flow".source =
    "${config.criomosHome.flow0511.clients}/bin/flow-0.51.1";
  home.file.".local/bin/flow-meta".source =
    "${config.criomosHome.flow0511.clients}/bin/flow-meta-0.51.1";
}
