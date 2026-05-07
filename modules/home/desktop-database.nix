{ lib, pkgs, ... }:

# User-local mimeinfo.cache regeneration.
#
# When a module ships a `.desktop` file via `home.file."./.local/share/applications/<name>.desktop"`,
# home-manager links it into place but does NOT refresh
# `~/.local/share/applications/mimeinfo.cache`. Without that cache,
# gio's app enumeration (the "Open With…" chooser dialog) cannot see
# the file's `MimeType=` claims — only the `mimeapps.list` default
# lookup works. Result: the entry shows as the registered default
# (when set) but never appears as an *option* alongside other apps.
#
# `xdg.desktopEntries.<name>` would do this automatically, but that
# API was producing no output here for reasons not pinned down. This
# activation hook is the unambiguous version: run
# `update-desktop-database` after `linkGeneration` on every activation.
# Idempotent and fast (under 50ms on this dataset).

{
  home.activation.updateUserDesktopDatabase =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.desktop-file-utils}/bin/update-desktop-database \
        -q $HOME/.local/share/applications || true
    '';
}
