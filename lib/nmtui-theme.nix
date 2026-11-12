{ lib }:
let
  newtRoles = [
    "root"
    "border"
    "window"
    "shadow"
    "title"
    "button"
    "actbutton"
    "checkbox"
    "actcheckbox"
    "entry"
    "label"
    "listbox"
    "actlistbox"
    "textbox"
    "acttextbox"
    "helpline"
    "roottext"
    "emptyscale"
    "fullscale"
    "disentry"
    "compactbutton"
    "actsellistbox"
    "sellistbox"
  ];

  activeNewtRoles = [
    "actbutton"
    "actcheckbox"
    "actlistbox"
    "acttextbox"
    "actsellistbox"
    "sellistbox"
  ];

  nmtNewtRoles = [
    "badLabel"
    "plainLabel"
    "disabledButton"
    "textboxWithBackground"
  ];

  renderRole =
    foreground: background: role:
    "${role}=${foreground},${background}";
  renderRoles =
    roles: foreground: background:
    lib.concatStringsSep ";" (map (renderRole foreground background) roles);
in
{
  inherit newtRoles activeNewtRoles nmtNewtRoles;

  renderNewtColors =
    foreground: background:
    let
      ordinaryRoles = builtins.filter (role: !(builtins.elem role activeNewtRoles)) newtRoles;
    in
    lib.concatStringsSep ";" [
      (renderRoles ordinaryRoles "default" "default")
      (renderRoles activeNewtRoles foreground background)
    ];

  renderNmtNewtColors = renderRoles nmtNewtRoles "default" "default";
}
