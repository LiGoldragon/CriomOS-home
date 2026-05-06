{
  lib,
  user,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (user) size;
in
mkIf size.atLeastMed {
  # The system codium.desktop ships without a `MimeType=` line, so
  # xdg-open's chooser dialog never offers Codium even when
  # mimeapps.list lists it as default. This user-local entry wins by
  # being earlier in `XDG_DATA_DIRS`, declares the MIME types Codium
  # actually handles, and otherwise mirrors the system entry verbatim.
  #
  # Written as `home.file` rather than `xdg.desktopEntries` because the
  # latter was producing no output in the home-manager generation here
  # (cause not pinned down; home.file is the unambiguous path).
  home.file.".local/share/applications/codium.desktop".text = ''
    [Desktop Entry]
    Actions=new-empty-window
    Categories=Utility;TextEditor;Development;IDE
    Comment=Code Editing. Redefined.
    Exec=codium %F
    GenericName=Text Editor
    Icon=vscodium
    Keywords=vscode
    MimeType=text/plain;text/markdown;text/x-c;text/x-c++;text/x-python;text/x-rust;text/x-go;text/x-shellscript;text/x-script.python;application/json;application/x-yaml;application/xml;application/x-shellscript;inode/directory;
    Name=VSCodium
    StartupNotify=true
    StartupWMClass=vscodium
    Type=Application
    Version=1.5

    [Desktop Action new-empty-window]
    Exec=codium --new-window %F
    Icon=vscodium
    Name=New Empty Window
  '';
}
