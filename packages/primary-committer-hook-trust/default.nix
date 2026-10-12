{ pkgs, inputs, ... }:
let
  trust = import ../../lib/primary-committer-hook-trust.nix { lib = pkgs.lib; };
  candidate = pkgs.callPackage ../../owned-agents/codex-next-candidate { };
  hash = builtins.unsafeDiscardStringContext (builtins.substring 0 12 (builtins.baseNameOf candidate.drvPath));
  hexis = inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
  declared = pkgs.writeText "primary-committer-hook-trust.json"
    (builtins.toJSON (trust.declared // { "$hexis" = { schema = 1; modes = trust.modes; }; }));
in pkgs.writeShellApplication {
  name = "primary-committer-hook-trust";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    if [ "$#" -ne 0 ]; then echo "This activation takes no arguments" >&2; exit 2; fi
    target="$HOME/.codex-next-${hash}/config.toml"
    if [ ! -f "$target" ] || [ -L "$target" ] || [ ! -O "$target" ]; then
      echo "Refusing absent, linked, or foreign candidate config" >&2; exit 1
    fi
    ${hexis}/bin/hexis apply --file "$target" --declared ${declared}
  '';
  passthru = { inherit declared hash; trust = { inherit (trust) key hash command; }; };
}
