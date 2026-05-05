{ pkgs, ... }:

let
  wtypeForHyprvoice = pkgs.writeShellScriptBin "wtype" ''
    set -eu

    delay_ms="''${HYPRVOICE_WTYPE_DELAY_MS:-25}"
    exec ${pkgs.wtype}/bin/wtype -d "$delay_ms" "$@"
  '';
in
pkgs.buildGoModule rec {
  pname = "hyprvoice";
  version = "1.0.2";

  src = pkgs.fetchFromGitHub {
    owner = "LeonardoTrapani";
    repo = "hyprvoice";
    rev = "v${version}";
    hash = "sha256-ng17y53L9cyxSjupSGKyZkBXOGneJrjprjvODYch6EE=";
  };

  vendorHash = "sha256-b1IsFlhj+xTQT/4PzL97YjVjjS7TQtcIsbeK3dLOxR4=";
  subPackages = [ "cmd/hyprvoice" ];
  patches = [ ./redact-transcript-logs.patch ];

  env.CGO_ENABLED = "0";
  nativeBuildInputs = [ pkgs.makeWrapper ];

  preCheck = ''
    export CI=true
  '';

  postInstall = ''
    wrapProgram $out/bin/hyprvoice \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.pipewire
          pkgs.libnotify
          wtypeForHyprvoice
          pkgs.wl-clipboard
        ]
      }
  '';

  meta = {
    description = "Voice-powered typing for Wayland desktops";
    homepage = "https://github.com/LeonardoTrapani/hyprvoice";
    license = pkgs.lib.licenses.mit;
    mainProgram = "hyprvoice";
    platforms = pkgs.lib.platforms.linux;
  };
}
