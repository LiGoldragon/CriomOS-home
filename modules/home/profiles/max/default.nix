{
  lib,
  pkgs,
  user,
  inputs,
  hexis,
  ...
}:
let
  inherit (lib) optionals mkIf mkMerge;
  inherit (user) isMultimediaDev size;

  codingPackages = [
    pkgs.pandoc
    inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.traycer
  ];

  # Per Li 2026-04-25: gimp, krita, calibre, inkscape stay Max-tier.
  # discord-ptb, firefox-bin removed.
  maxMultimediaPackages = with pkgs; [
    krita
    calibre
    virt-manager
    gimp
    inkscape
  ];

  candidatePackages = with pkgs; [
    qpwgraph
    tenacity
    lapce
    pavucontrol # TODO: pwvucontrol doesnt display virtual sources
  ];

  mentciPackages = [
    inputs.mentci-egui.packages.${pkgs.stdenv.hostPlatform.system}.default
    (pkgs.callPackage ../../../../packages/mentci { inherit inputs; })
  ];

  # bottles removed 2026-08-14: bottles-65.4 FHS Wine environment pulls in
  # i686-linux packages (dosbox, openldap-2.6.13, gtk4, sdl2-compat) whose
  # new dependency hashes are absent from all configured binary caches and
  # cannot be built on the x86_64-only remote builder. Re-add once the
  # nixos cache carries the new i686 derivations or an i686 builder is added.
  windowsEmulationsPackages = [];

in
mkMerge [
  # Large-tier baseline: most "max profile" packages are now Large per
  # the bulk size-Max -> Large rule. Specific heavy items that stay
  # Max-only are wrapped in their own mkIf below.
  (mkIf size.large {
    home.packages =
      with pkgs;
      [
        # freecad # broken
        karere
        gitkraken
      ]
      ++ windowsEmulationsPackages
      ++ codingPackages;

    programs.chromium = {
      enable = true;
      # Wrap google-chrome so the chrome 144 MCP autoConnect toggle
      # ("Allow remote debugging for this browser instance" at
      # chrome://inspect/#remote-debugging) gets seeded `true` on first
      # launch via hexis once-mode. The toggle persists at
      # `/devtools/remote_debugging/user-enabled` in `Local State`
      # (Chrome's global state file, not Default/Preferences).
      # Once seeded, the user owns it forever; toggling it off in the
      # UI sticks because the once-marker prevents re-seeding.
      #
      # processName="chrome" — the actual Chrome binary process is
      # `chrome`; `google-chrome` is just the launcher script. The
      # pgrep guard skips hexis apply if Chrome is already running,
      # avoiding a race against the in-memory copy of Local State.
      package = inputs.hexis.lib.wrapWithHexis {
        inherit pkgs hexis;
        name = "google-chrome";
        processName = "chrome";
        package = pkgs.google-chrome;
        file = "$HOME/.config/google-chrome/Local State";
        declared = {
          devtools.remote_debugging.user-enabled = true;
        };
        modes = {
          "/devtools/remote_debugging/user-enabled" = "once";
        };
      };
    };
  })

  # Max-tier exceptions per Li 2026-04-25: obs-studio + gimp/krita/
  # calibre/inkscape (when isMultimediaDev) live at size.max only.
  (mkIf size.max {
    home.packages = mentciPackages ++ optionals isMultimediaDev maxMultimediaPackages;

    programs.obs-studio = {
      enable = true;
      package = pkgs.obs-studio;
      plugins = with pkgs.obs-studio-plugins; [
        droidcam-obs
        wlrobs
        obs-pipewire-audio-capture
        # advanced-scene-switcher # TODO broken.build
        obs-move-transition
        obs-vaapi
        waveform
      ];
    };
  })
]
