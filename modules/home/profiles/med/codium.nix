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
  # actually handles, and leaves the rest of the entry verbatim.
  xdg.desktopEntries.codium = {
    name = "VSCodium";
    genericName = "Text Editor";
    comment = "Code Editing. Redefined.";
    icon = "vscodium";
    exec = "codium %F";
    categories = [
      "Utility"
      "TextEditor"
      "Development"
      "IDE"
    ];
    startupNotify = true;
    type = "Application";
    mimeType = [
      "text/plain"
      "text/markdown"
      "text/x-c"
      "text/x-c++"
      "text/x-python"
      "text/x-rust"
      "text/x-go"
      "text/x-shellscript"
      "text/x-script.python"
      "application/json"
      "application/x-yaml"
      "application/xml"
      "application/x-shellscript"
      "inode/directory"
    ];
    settings = {
      Keywords = "vscode";
      StartupWMClass = "vscodium";
    };
    actions.new-empty-window = {
      name = "New Empty Window";
      exec = "codium --new-window %F";
      icon = "vscodium";
    };
  };
}
