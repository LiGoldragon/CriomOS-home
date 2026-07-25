{
  lib,
  pkgs,
  user,
  ...
}:
let
  inherit (lib) mkIf;
  inherit (user) size;

  codiumOpen = pkgs.writeShellScript "criomos-codium-open" ''
    set -euo pipefail

    targets=()
    hasPosition=0

    decodeFileLocator() {
      ${pkgs.python3}/bin/python3 -c 'import sys, urllib.parse; parsed = urllib.parse.urlparse(sys.argv[1]); print(urllib.parse.unquote(parsed.path) if parsed.scheme == "file" else sys.argv[1])' "$1"
    }

    for raw in "$@"; do
      trimmed=$(printf '%s' "$raw" | ${pkgs.gnused}/bin/sed 's/[[:space:]]*$//')
      if [ -z "$trimmed" ]; then
        continue
      fi

      if [[ "$trimmed" == file://* ]]; then
        candidate=$(decodeFileLocator "$trimmed")
      else
        candidate="$trimmed"
      fi

      if [[ "$candidate" =~ ^[[:alpha:]][[:alnum:]+.-]*:// ]]; then
        targets+=("$candidate")
        continue
      fi

      pathCandidate="$candidate"
      lineNumber=""
      columnNumber=""

      if [[ "$candidate" =~ ^(.+):([0-9]+):([0-9]+)$ ]]; then
        pathCandidate="''${BASH_REMATCH[1]}"
        lineNumber="''${BASH_REMATCH[2]}"
        columnNumber="''${BASH_REMATCH[3]}"
      elif [[ "$candidate" =~ ^(.+):([0-9]+)$ ]]; then
        pathCandidate="''${BASH_REMATCH[1]}"
        lineNumber="''${BASH_REMATCH[2]}"
      fi

      resolved=""
      if [ -e "$pathCandidate" ]; then
        resolved="$pathCandidate"
      elif [[ "$pathCandidate" != /* ]] && [ -e "$HOME/primary/$pathCandidate" ]; then
        resolved="$HOME/primary/$pathCandidate"
      fi

      if [ -n "$resolved" ]; then
        if [ -n "$lineNumber" ]; then
          target="$resolved:$lineNumber"
          if [ -n "$columnNumber" ]; then
            target="$target:$columnNumber"
          fi
          targets+=("$target")
          hasPosition=1
        else
          targets+=("$resolved")
        fi
      else
        targets+=("$trimmed")
      fi
    done

    if [ "''${#targets[@]}" -eq 0 ]; then
      exec codium
    fi

    if [ "$hasPosition" -eq 1 ]; then
      exec codium --goto "''${targets[@]}"
    else
      exec codium "''${targets[@]}"
    fi
  '';
in
mkIf size.medium {
  # The system codium.desktop ships without a `MimeType=` line, so
  # xdg-open's chooser dialog never offers Codium even when
  # mimeapps.list lists it as default. This user-local entry wins by
  # being earlier in `XDG_DATA_DIRS`, declares the MIME types Codium
  # actually handles, and otherwise mirrors the system entry verbatim.
  #
  # Written as `home.file` rather than `xdg.desktopEntries` because the
  # latter was producing no output in the home-manager generation here
  # (cause not pinned down; home.file is the unambiguous path).
  # Cache refresh (so the chooser actually sees this file) is wired
  # cluster-wide in `modules/home/desktop-database.nix`.
  home.file.".local/share/applications/codium.desktop".text = ''
    [Desktop Entry]
    Actions=new-empty-window
    Categories=Utility;TextEditor;Development;IDE
    Comment=Code Editing. Redefined.
    Exec=${codiumOpen} %F
    GenericName=Text Editor
    Icon=vscodium
    Keywords=vscode
    MimeType=text/plain;text/markdown;text/x-c;text/x-c++;text/x-python;text/rust;text/x-rust;text/x-go;text/x-shellscript;text/x-script.python;application/json;application/x-yaml;application/xml;application/x-shellscript;application/x-zerosize;inode/directory;
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
