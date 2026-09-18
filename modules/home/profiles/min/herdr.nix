{ ... }:
{
  xdg.configFile."herdr/config.toml".text = ''
    [ui.toast]
    delivery = "terminal"
  '';
}
