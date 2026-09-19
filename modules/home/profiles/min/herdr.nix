{ ... }:
{
  xdg.configFile."herdr/config.toml".text = ''
    [theme]
    auto_switch = true
    dark_name = "catppuccin"
    light_name = "catppuccin-latte"

    [ui.toast]
    delivery = "terminal"
  '';
}
