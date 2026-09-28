{ user, ... }:
let
  # Cluster-wide textSize ladder — single source of truth. Each
  # consumer (ghostty, emacs, stylix) reads the exposed `textScale`
  # module arg rather than redefining the mapping locally.
  fontPt = {
    ExtraSmall = 11;
    Small = 12;
    Medium = 14;
    Large = 16;
    ExtraLarge = 18;
  }.${user.textSize};
in
{
  _module.args.textScale = {
    inherit fontPt;
    # Emacs `:height` is in 1/10 pt units.
    emacsHeight = fontPt * 10;
  };
}
