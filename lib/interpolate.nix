# Nix mirror of the updater's {name} interpolation.
template: vars:
builtins.replaceStrings (map (name: "{${name}}") (
  builtins.attrNames vars
)) (builtins.attrValues vars) template
