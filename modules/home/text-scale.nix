{ user, ... }:
let
  # Cluster-wide textSize ladder — single source of truth. Each
  # consumer (ghostty, emacs, codium, stylix) reads the
  # exposed `textScale` module arg rather than redefining the
  # mapping locally.
  fontPt = {
    ExtraSmall = 11;
    Small = 12;
    Medium = 14;
    Large = 16;
    ExtraLarge = 18;
  }.${user.textSize};

  codiumZoom = {
    ExtraSmall = -1;
    Small = -0.5;
    Medium = 0;
    Large = 0.5;
    ExtraLarge = 1;
  }.${user.textSize};
in
{
  _module.args.textScale = {
    inherit fontPt codiumZoom;
    # Emacs `:height` is in 1/10 pt units.
    emacsHeight = fontPt * 10;
  };
}
