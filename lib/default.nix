{ ... }:
{
  # Blueprint requires a real lib entrypoint whenever this directory exists.
  # Package-local helpers remain imported explicitly by their owning
  # derivations; they are not a second package authority.
}
