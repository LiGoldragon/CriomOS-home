{ ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
  };
  home.sessionVariables.EDITOR = "nvim";
}
