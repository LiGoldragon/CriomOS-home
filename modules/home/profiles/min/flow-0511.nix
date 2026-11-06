# Flow Nexus 0.51.1 runs beside 0.51 while its authenticated seats adopt it.
{ config, lib, ... }:
{
  imports = [
    (import ./flow-nexus-version.nix {
      version = "0.51.2";
      slug = "0511";
    })
  ];

  # The unversioned clients move only when this Home generation activates.
  home.file.".local/bin/flow".source =
    "${config.criomosHome.flow0511.clients}/bin/flow-0.51.2";
  home.file.".local/bin/flow-meta".source =
    "${config.criomosHome.flow0511.clients}/bin/flow-meta-0.51.2";

  # Adopt only the two clients installed with the running 0.51 Nexus. Home
  # Manager can then own their unversioned names without treating those
  # retained links as user files. A later activation accepts its own links.
  home.activation.adoptFlow051Clients = lib.hm.dag.entryBefore [ "checkLinkTargets" ] ''
    adopt_client() {
      path="$1"
      relative="$2"
      predecessor="$3"
      if [ ! -e "$path" ] && [ ! -L "$path" ]; then
        return
      fi
      if [ ! -L "$path" ]; then
        echo "Refusing Flow client adoption: $path is not a symbolic link" >&2
        exit 1
      fi
      if [ "$(readlink -- "$path")" = "$predecessor" ]; then
        rm -- "$path"
        return
      fi
      if [ -n "''${oldGenPath:-}" ] \
        && [ "$(readlink -f -- "$path")" = "$(readlink -f -- "$oldGenPath/home-files/$relative")" ]; then
        return
      fi
      echo "Refusing Flow client adoption: $path is not the declared 0.51 client" >&2
      exit 1
    }

    adopt_client \
      "$HOME/.local/bin/flow" \
      ".local/bin/flow" \
      "$HOME/.local/state/flow-gcroots/clients-051/bin/flow-0.51"
    adopt_client \
      "$HOME/.local/bin/flow-meta" \
      ".local/bin/flow-meta" \
      "$HOME/.local/state/flow-gcroots/clients-051/bin/flow-meta-0.51"
  '';
}
