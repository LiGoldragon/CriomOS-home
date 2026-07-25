{
  pkgs,
  lib,
  user,
  inputs,
  hexis,
  textScale,
  ...
}:
let
  inherit (user) size;
  codiumPackage = pkgs.callPackage ../../../../packages/vscodium-casual { };

  lifecycleSource = pkgs.replaceVars ./claude-lifecycle.sh {
    FLOCK = "${pkgs.util-linux}/bin/flock";
    JQ = "${pkgs.jq}/bin/jq";
    READLINK = "${pkgs.coreutils}/bin/readlink";
  };
  codiumClaudeLifecycle = pkgs.writeShellScriptBin "criomos-codium-claude-lifecycle" (
    builtins.readFile lifecycleSource
  );

  codiumManagedPackage = pkgs.symlinkJoin {
    name = "vscodium-casual-managed";
    pname = codiumPackage.pname;
    version = codiumPackage.version;
    paths = [ codiumPackage ];
    meta = codiumPackage.meta;
    postBuild = ''
      rm -f $out/bin/codium
      cat > $out/bin/codium <<'EOF'
      #!${pkgs.runtimeShell}
      set -euo pipefail
      lock="''${CRIOMOS_VSCODIUM_LOCK_FILE:-''${XDG_STATE_HOME:-$HOME/.local/state}/criomos/vscodium-claude}/lifecycle.lock"
      mkdir -p "$(dirname "$lock")"
      exec 9>"$lock"
      ${pkgs.util-linux}/bin/flock -x 9
      CRIOMOS_VSCODIUM_LOCK_HELD=1 ${codiumClaudeLifecycle}/bin/criomos-codium-claude-lifecycle --launch
      ${pkgs.util-linux}/bin/flock -s 9
      exec ${codiumPackage}/bin/codium "$@"
      EOF
      chmod +x $out/bin/codium
    '';
  };

  # Flake inputs of `type = "file"` always materialize as a store path
  # named `source` (no extension). nixpkgs' `unpack-vsix-setup-hook`
  # dispatches on the file extension though — `.vsix` triggers unzip.
  # Wrap each VSIX-input in a tiny rename derivation so the hook
  # recognizes it.
  vsixFromInput =
    name: input:
    pkgs.runCommand name { } ''
      cp ${input} $out
    '';

  # `pkgs.open-vsx` comes from CriomOS-pkgs's overlay-applied
  # nix-vscode-extensions overlay — built in our pkgs context where
  # config.allowUnfree = true, so unfree extensions like
  # anthropic.claude-code resolve cleanly. Reading from the flake
  # input's own outputs (inputs.nix-vscode-extensions.extensions.<system>.open-vsx)
  # would use their pkgs which has allowUnfree commented out and
  # rejects the package.
  ovsx = pkgs.open-vsx;

  # visualjj — VSIX comes from `inputs.visualjj-vsix` (a `type = file`
  # flake input pinned to a versioned open-vsx URL), buildVscodeMarketplaceExtension
  # wraps it. Avoids both manual sha256 maintenance AND the
  # nix-vscode-extensions unfree-license gate that fires inside
  # home-manager's extension evaluation even with allowUnfree set.
  # `postInstall` patchelf step targets the bundled native jj binary
  # which ships linked against `/lib64/ld-linux-x86-64.so.2`.
  visualjj = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "visualjj";
      publisher = "visualjj";
      version = "0.28.1";
    };
    vsix = vsixFromInput "visualjj-0.28.1.vsix" inputs.visualjj-vsix;
    postInstall = ''
      jj=$out/share/vscode/extensions/visualjj.visualjj/dist/bin/jj
      if [ -f "$jj" ]; then
        ${pkgs.patchelf}/bin/patchelf \
          --set-interpreter "$(cat ${pkgs.stdenv.cc}/nix-support/dynamic-linker)" \
          --set-rpath "${lib.makeLibraryPath [ pkgs.stdenv.cc.cc.lib ]}" \
          "$jj"
      fi
    '';
  };

  # Same flake-input-as-VSIX pattern as visualjj — nix-vscode-extensions
  # provides claude-code but its meta.license = unfree trips a check
  # that allowUnfree=true at every level couldn't bypass.
  #
  # The VSIX ships a generic-Linux ELF at `resources/native-binary/claude`
  # which fails on NixOS with 'Could not start dynamically linked
  # executable ... NixOS cannot run dynamically linked executables
  # intended for generic linux environments out of the box'. Replace it
  # with the workspace-gated wrapper around the properly-nix-built binary from
  # the llm-agents.nix flake input. The wrapper keeps Claude private memory
  # opt-in instead of default for extension launches too.
  claude-code-codium = pkgs.vscode-utils.buildVscodeMarketplaceExtension {
    mktplcRef = {
      name = "claude-code";
      publisher = "anthropic";
      version = "2.1.215";
    };
    vsix = vsixFromInput "claude-code-2.1.215.vsix" inputs.claude-code-vsix;
    postInstall = ''
      bin_dir=$out/share/vscode/extensions/anthropic.claude-code/resources/native-binary
      if [ -d "$bin_dir" ]; then
        rm -f "$bin_dir/claude"
        ln -s "${
          inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claude-code
        }/bin/claude" "$bin_dir/claude"
      fi
    '';
  };

  # All aski-related code dropped per Li 2026-04-25.

  nixSettings = {
    # Theme — stylix generates base16 theme, darkman switches via portal
    "window.autoDetectColorScheme" = true;
    "workbench.preferredDarkColorTheme" = "Default Dark Modern";
    "workbench.preferredLightColorTheme" = "Default Light Modern";

    # jj uses git as backend — VSCode's SCM API surface assumes vscode.git is available,
    # so we keep it enabled for extensions that read VCS state (vscode-pi, etc).
    # VisualJJ colocates in the same SCM panel for the actual jj workflow.
    "git.enabled" = true;
    "git.autoRepositoryDetection" = true;
    "visualjj.showSourceControlColocated" = true;

    # direnv — explicitly do NOT auto-restart the extension host on
    # direnv state changes. Auto-restart kills every in-flight Claude
    # Code agent in the sidebar/panel when the user crosses a directory
    # with/without `.envrc`, edits flake.lock, or hits a watch_file
    # path. Archive incident 2026-04-26: lost two agents to a single jj
    # commit+push from a mentci-rooted Codium window.
    "direnv.restart.automatic" = false;

    # VSCodium is the casual glossing / markdown-preview editor. Keep
    # syntax-oriented extensions, but do not start language servers from
    # Codium windows.
    "nix.enableLanguageServer" = false;
    "nix.serverPath" = null;
    "rust-analyzer.server.path" = null;

    # Terminal
    "terminal.integrated.defaultProfile.linux" = "zsh";

    # Suppress welcome tab and extension walkthroughs
    "workbench.startupEditor" = "none";
    "workbench.welcomePage.walkthroughs.openOnInstall" = false;

    # Extensions managed by Nix — no marketplace updates
    "extensions.autoUpdate" = false;
    "extensions.autoCheckUpdates" = false;

    # Telemetry off
    "telemetry.telemetryLevel" = "off";
    "update.mode" = "none";

    # Editor
    "window.openFilesInNewWindow" = "default";
    "editor.renderWhitespace" = "boundary";
    "editor.minimap.enabled" = false;
    "files.trimTrailingWhitespace" = true;
    "files.insertFinalNewline" = true;

    # User-driven UI size. window.zoomLevel scales every surface
    # in Codium uniformly (chrome, panels, editor) — one knob, one
    # mental model. We deliberately do NOT also override
    # editor.fontSize: combining the two is multiplicative and
    # makes the editor pane drift away from the chrome.
    "window.zoomLevel" = textScale.codiumZoom;
  };

in
lib.mkIf size.medium {

  programs.vscode = {
    enable = true;
    package = codiumManagedPackage;

    profiles.default = {
      extensions = [
        visualjj
        claude-code-codium
        ovsx.openai.chatgpt
        ovsx.cdervis.vscode-pi
        pkgs.vscode-extensions.mkhl.direnv
        pkgs.vscode-extensions.jnoortheen.nix-ide
        # Drift cleanup — three extensions had been installed manually
        # through the marketplace UI; lifted here so Nix is the
        # single source of truth (`extensions.autoUpdate = false`
        # already prevents marketplace-side drift).
        ovsx.zaaack.markdown-editor
        ovsx.lyuwenhan.mermaid-snap
        ovsx.onlyutkarsh.mermaid-diagram-lens
      ];
    };
  };

  # VSCodium is installed in the medium profile, but it only owns
  # EDITOR/VISUAL and text/source MIME defaults when Horizon projects
  # Codium as this user's preferred editor. A user preference for Emacs
  # must remain able to select emacsclient even while Codium is present
  # as an auxiliary editor.
  home.sessionVariables = lib.mkIf (user.preferredEditor == "Codium") {
    EDITOR = lib.mkForce "codium --wait";
    VISUAL = lib.mkForce "codium --wait";
  };

  xdg.mimeApps.defaultApplications = lib.mkIf (user.preferredEditor == "Codium") (
    builtins.listToAttrs (
      map
        (t: {
          name = t;
          value = lib.mkForce "codium.desktop";
        })
        [
          "text/plain"
          "text/markdown"
          "text/x-markdown"
          "text/x-python"
          "text/x-shellscript"
          "text/rust"
          "text/x-c"
          "text/x-c++"
          "text/x-rust"
          "text/x-go"
          "text/x-java"
          "text/x-toml"
          "text/x-nix"
          "text/x-lua"
          "text/x-diff"
          "text/x-log"
          "text/csv"
          "text/xml"
          "application/json"
          "application/x-yaml"
          "application/xml"
          "application/toml"
          "application/x-shellscript"
          "application/x-zerosize"
        ]
    )
  );

  # Replaces the broken `mkJsonMerge` shallow-merge helper. hexis does
  # a real RFC-7396-shaped deep merge: declared keys win where they
  # speak, user drift survives at any pointer declared doesn't mention.
  # All keys default to `ensure` mode here — declared overlays the
  # defaults, user overrides survive at sibling keys (the
  # `[python].wordWrap`-clobber case the old helper got wrong).
  home.packages = [ codiumClaudeLifecycle ];

  home.activation.bootstrapMutableClaudeCodeExtension = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
    run ${codiumClaudeLifecycle}/bin/criomos-codium-claude-lifecycle --bootstrap
  '';

  home.activation.replaceMutableClaudeCodeExtension = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    run ${codiumClaudeLifecycle}/bin/criomos-codium-claude-lifecycle --activate
  '';

  home.activation.mergeVscodiumSettings = inputs.hexis.lib.mkManagedConfig {
    inherit lib pkgs hexis;
    file = "$HOME/.config/VSCodium/User/settings.json";
    declared = nixSettings;
  };
}
