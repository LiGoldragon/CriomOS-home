{ ... }:
{
  programs.neovim = {
    enable = true;
    vimAlias = true;
    # Keep Neovim as a plain editor. No plugins or language-service
    # configuration are declared here, so tooling remains an explicit action.
    withNodeJs = false;
    withPython3 = false;
    withRuby = false;
  };
  home.sessionVariables.EDITOR = "nvim";
}
