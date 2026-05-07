{ inputs, pkgs, ... }:

let
  craneLib = inputs.crane.mkLib pkgs;

  commonArguments = {
    pname = "whisrs";
    version = "0.1.11";
    src = craneLib.cleanCargoSource inputs.whisrs-src;

    strictDeps = true;
    cargoExtraArgs = "--no-default-features --features tray";

    nativeBuildInputs = with pkgs; [
      pkg-config
      llvmPackages.clang
      rustPlatform.bindgenHook
    ];

    buildInputs = with pkgs; [
      alsa-lib
      libxkbcommon
    ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArguments;
in
craneLib.buildPackage (
  commonArguments
  // {
    inherit cargoArtifacts;

    patches = [
      ./privacy.patch
      ./clipboard-mode.patch
      ./transcript-recovery.patch
      ./tray-icon-theme.patch
      # `whisrs spool {list,retry,drop}` subcommands + migration of the
      # legacy `~/.cache/whisrs/recovery/` cache-class storage to the
      # state-class `$XDG_STATE_HOME/whisrs/spool/`. The systemd unit
      # `whisrs-spool-retry.service` (wired in
      # `modules/home/profiles/min/dictation.nix`) calls `whisrs spool
      # retry --all --auto` from `network-online.target` so a failed
      # transcription is retried when connectivity returns.
      # See ~/primary/reports/system-specialist/2-voice-typing-recovery-design.md
      ./spool-recovery.patch
    ];

    nativeBuildInputs = commonArguments.nativeBuildInputs ++ [
      pkgs.makeWrapper
    ];

    preCheck = ''
      export HOME="$TMPDIR"
      export XDG_CACHE_HOME="$TMPDIR/cache"
      export XDG_DATA_HOME="$TMPDIR/data"
      mkdir -p "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
    '';

    postInstall = ''
      install -Dm644 ${inputs.whisrs-src}/contrib/whisrs.1 $out/share/man/man1/whisrs.1
      install -Dm644 ${inputs.whisrs-src}/contrib/whisrsd.1 $out/share/man/man1/whisrsd.1
      install -Dm644 ${./whisrs-idle.svg} $out/share/icons/hicolor/scalable/status/whisrs-idle.svg
      install -Dm644 ${./whisrs-recording.svg} $out/share/icons/hicolor/scalable/status/whisrs-recording.svg
      install -Dm644 ${./whisrs-transcribing.svg} $out/share/icons/hicolor/scalable/status/whisrs-transcribing.svg

      mv $out/bin/whisrs $out/bin/whisrs-unwrapped
      makeWrapper $out/bin/whisrs-unwrapped $out/bin/whisrs \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.systemd
            pkgs.coreutils
          ]
        }

      wrapProgram $out/bin/whisrsd \
        --set WHISRS_ICON_THEME_PATH $out/share/icons/hicolor/scalable/status \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.niri
            pkgs.wl-clipboard
            pkgs.systemd
            pkgs.libnotify
            pkgs.coreutils
            # ffmpeg is the daemon's encoder for OPUS-in-OGG spool
            # files (per spool-recovery.patch's `encode_opus_ogg`).
            # Headless build is enough — we never decode video.
            pkgs.ffmpeg-headless
          ]
        }
    '';

    meta = {
      description = "Linux-first voice-to-text dictation tool";
      homepage = "https://github.com/y0sif/whisrs";
      license = pkgs.lib.licenses.mit;
      mainProgram = "whisrs";
      platforms = pkgs.lib.platforms.linux;
    };
  }
)
