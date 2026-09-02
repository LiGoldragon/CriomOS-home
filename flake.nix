{
  description = "CriomOS-home — home profile. Standalone home-manager flake consumed by CriomOS.";

  inputs = {
    nixpkgs.url = "github:LiGoldragon/nixpkgs?ref=main";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    crane.url = "github:ipetkov/crane";

    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    system.url = "path:./stubs/no-system";

    pkgs.url = "github:LiGoldragon/CriomOS-pkgs";
    pkgs.inputs.nixpkgs.follows = "nixpkgs";
    pkgs.inputs.system.follows = "system";

    # Upstream source for the centrally overridden yt-dlp package. Keep this
    # non-flake input independently current with `nix flake update yt-dlp`.
    yt-dlp = {
      url = "github:yt-dlp/yt-dlp";
      flake = false;
    };

    horizon.url = "path:./stubs/no-horizon";

    # Compositor + shell.
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:LiGoldragon/noctalia/9778437e8bd326d6d82340fff6b0400eee2caf6f";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";

    # Styling.
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # Editor — vscodium extensions.
    # Note: the open-vsx + vscode-marketplace catalogues come into
    # scope via `pkgs.open-vsx` from CriomOS-pkgs (which applies
    # nix-vscode-extensions's overlay against a pkgs that has
    # allowUnfree=true). This file consumes `pkgs.open-vsx` directly,
    # so no nix-vscode-extensions input is needed here.

    # visualjj VSIX — fetched as a versioned flake input so the lock-
    # file hash (auto-resolved by nix flake update) replaces a manual
    # sha256. The nix-vscode-extensions flake's visualjj has a
    # nixpkgs-side meta.license = unfree gate that fires inside
    # home-manager's extension evaluation even when allowUnfree is set,
    # so we keep using `buildVscodeMarketplaceExtension` and source the
    # VSIX from this input. Bump the version in the URL when upstream
    # ships a new release; `nix flake update visualjj-vsix` then picks
    # up the new content hash without any code edit.
    visualjj-vsix = {
      type = "file";
      url = "https://open-vsx.org/api/visualjj/visualjj/linux-x64/0.28.1/file/visualjj.visualjj-0.28.1@linux-x64.vsix";
      flake = false;
    };

    # claude-code VSIX — same `type = file` pattern as visualjj. Both
    # nix-vscode-extensions and the nixpkgs-side definition tag claude-
    # code as `meta.license = unfree`, which trips home-manager's
    # vscode-extensions evaluation regardless of allowUnfree being
    # set at every layer we tried (CriomOS-pkgs's pkgs.config, the
    # overlay-extended pkgs, even nixpkgs.config.allowUnfree at the
    # nixos level via mkOverride 0). Bypassing the catalogue + using
    # buildVscodeMarketplaceExtension on the raw VSIX sidesteps the
    # gate entirely.
    claude-code-vsix = {
      type = "file";
      url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/anthropic/vsextensions/claude-code/2.1.258/vspackage";
      flake = false;
    };

    # Codex sidebar VSIX — keep the editor surface on its own versioned
    # input, alongside the independently pinned Codex CLI below.  The
    # Open VSX catalogue is deliberately not the update authority here:
    # Codium marketplace checks are disabled, and its catalogue cadence can
    # otherwise leave the sidebar behind the TUI.  For a coordinated Codex
    # refresh, update this URL, run `nix flake update codex-chatgpt-vsix`, and
    # run the VSCodium lifecycle check before deploying.
    codex-chatgpt-vsix = {
      type = "file";
      url = "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/openai/vsextensions/chatgpt/26.5825.51511/vspackage?targetPlatform=linux-x64";
      flake = false;
    };

    # `substack` CLI — its own flake, exposes packages.<system>.default.
    substack-cli.url = "github:LiGoldragon/substack-cli";
    substack-cli.inputs.nixpkgs.follows = "nixpkgs";

    # `claude-answers` — recall your answers to Claude Code's questions from
    # session transcripts. Its own flake, exposes packages.<system>.default.
    claude-answers.url = "github:LiGoldragon/claude-answers";
    claude-answers.inputs.nixpkgs.follows = "nixpkgs";

    # Listener — CriomOS speech-to-text runtime for the daily dictation path.
    listener.url = "github:LiGoldragon/listener";
    listener.inputs.nixpkgs.follows = "nixpkgs";
    listener.inputs.crane.follows = "crane";

    # Harness owns parent-only flow identity claims. Home installs the pinned
    # helper in the minimum profile beside the Codex and Claude clients.
    harness.url = "github:LiGoldragon/harness/363a5bec61d05a628750e00e7b03d8de7f8693a8";
    harness.inputs.nixpkgs.follows = "nixpkgs";

    # The packaging recipe is public and immutable; its proprietary payload is
    # a separate local input.  The locked NAR hash identifies the exact
    # user-supplied installer without committing, hosting, or redistributing it.
    wispr-flow-linux.url = "github:LiGoldragon/wispr-flow-linux?rev=003ccc2890c1709c7e966e96db5d4cde5ee82813";
    wispr-flow-linux.inputs.nixpkgs.follows = "nixpkgs";
    wispr-flow-installer = {
      url = "path:/home/li/.local/share/wispr-flow-installer/wispr-flow-setup-1.6.7.exe";
      flake = false;
    };

    # `annas` — Anna's Archive book/article search + download CLI. Upstream
    # (iosifache/annas-mcp) has no flake; consumed as non-flake source and
    # built inline via buildGoModule in modules/home/profiles/med/cli-tools.nix.
    # Wrapped with gopass-driven env injection (see lore/annas/basic-usage.md).
    annas-mcp = {
      url = "github:LiGoldragon/annas-mcp?ref=v0.0.5";
      flake = false;
    };

    # Shared helpers (importJSON) cross-consumed with CriomOS. The
    # mkJsonMerge helper was retired in favour of hexis (below).
    criomos-lib.url = "github:LiGoldragon/CriomOS-lib";

    # Managed-mutable config reconciliation — replaces the broken
    # shallow-merge `mkJsonMerge`. Provides `hexis apply` plus an HM
    # helper at `inputs.hexis.lib.mkManagedConfig`.
    hexis.url = "github:LiGoldragon/hexis";
    hexis.inputs.nixpkgs.follows = "nixpkgs";

    # AI coding agents are owned by the local package constructors under
    # `packages/{codex,claude-code,chatgpt,claude-desktop}`. Keep independent
    # VSIX inputs versioned separately from those package derivations.
    # Agent harness managers.  Herdr supplies its official tagged flake;
    # Orca remains packaged in its dedicated repository and Home consumes
    # only that pinned package output.
    herdr.url = "github:herdrdev/herdr/v0.8.2";
    orca-ide.url = "github:Samuka007/nix-orca/249a8d3c1bb2842ddec882ef2c1afd28c426b19e";

    # Google Workspace CLI for no-MCP assistant access to Gmail, Drive,
    # Calendar, Docs, Sheets, Slides, Tasks, and People/Contacts.
    google-workspace-cli.url = "github:googleworkspace/cli";
    google-workspace-cli.inputs.nixpkgs.follows = "nixpkgs";

    # Chroma — unified visual-state daemon (theme + warmth + brightness).
    # Replaces darkman + the nightshift-* services + the brightness shell
    # wrapper. Consumed in modules/home/profiles/min/chroma.nix.
    chroma.url = "github:LiGoldragon/chroma/1b626d9dc325459be6c825d0c5a59a7d245d1edd";
    chroma.inputs.nixpkgs.follows = "nixpkgs";

    # Resident Emacs projection for Chroma's desired theme state.  Home owns
    # the concrete Ignis themes and supplies this package its exact Emacs set.
    chroma-emacs.url = "github:LiGoldragon/chroma-emacs/119a231358cf69c16161812caf69fff4b726be5c";
    chroma-emacs.inputs.nixpkgs.follows = "nixpkgs";

    # Spirit owns the coherent daemon, judge, judge-config, and provider
    # derivation set. Home supplies paths and unit policy but never selects
    # those service component versions independently.
    spirit.url = "github:LiGoldragon/spirit/008d8ca0e4a309bdd922fae61681cdc97a484bac";
    spirit.inputs.nixpkgs.follows = "nixpkgs";

    # Agent — retained schema-derived local provider service and CLI. It is
    # independent of the Spirit-owned judge/provider composition.
    agent.url = "github:LiGoldragon/agent/3a3534931be790e63d3db01bbd238ad044b2d35f";
    agent.inputs.nixpkgs.follows = "nixpkgs";
    agent.inputs.crane.follows = "crane";

    # Aggregator — local transcript/evidence recovery daemon. Pinned to the
    # audited source accepted for Home-profile deployment.
    aggregator.url = "github:LiGoldragon/aggregator/f777eb2a6e92d26eb0ce7315586c939c071111a0";
    aggregator.inputs.nixpkgs.follows = "nixpkgs";
    aggregator.inputs.crane.follows = "crane";

    # Orchestrate Nexus — per-user path-reservation Nexus. Its executable owns
    # the default fresh Sema store and its ordinary/meta XDG sockets; Home
    # supplies lifecycle and client socket bindings without a bootstrap frame.
    orchestrate.url = "github:LiGoldragon/orchestrate/e0f3bc5e8b963089e560383b2a4eb7d30cda1f82";
    orchestrate.inputs.nixpkgs.follows = "nixpkgs";

    # Message — the messenger: stateful local messaging daemon owning the
    # durable agent-identity map, delivery registry, message ledger,
    # per-recipient inboxes, and thread index (messenger.sema). Consumed in
    # modules/home/profiles/min/message.nix, which gives it a systemd --user
    # supervisor. Pinned to v0.10.2: the phase-3 messenger promotion
    # (converged contracts, delivery legs, PTY control-socket delivery) plus
    # the additive v2 -> v3 store migration — the deployed store, born at v2,
    # is preserved aside and re-stamped on first open — on the
    # incident-hardened sema-engine 0.11.2 orchestrate 0.14.1 runs.
    message.url = "github:LiGoldragon/message/bf7295641bb2f15ad86622f242909a0646166ced";
    message.inputs.nixpkgs.follows = "nixpkgs";
    message.inputs.crane.follows = "crane";

    # Mentci approval daemon source, packaged locally because it does not
    # expose a flake.
    mentci-src = {
      url = "github:LiGoldragon/mentci/235b1b44ecd93857df60c36a2ca4fa16fab5984f";
      flake = false;
    };

    # `pi` (earendil-works/pi coding-agent CLI) — TypeScript npm
    # monorepo with no upstream flake. Consumed as a non-flake source
    # input and built locally via `packages/pi/default.nix`
    # (buildNpmPackage over the `packages/coding-agent` workspace).
    # Replaces the previous pi-mentci wrapper flake (dropped 2026-04-25).
    pi-src = {
      url = "github:earendil-works/pi?ref=v0.84.1";
      flake = false;
    };

    # Agent Intercom is a coordinated upstream family. These immutable
    # source inputs deliberately move as one protocol-v3 set; the package
    # derivation assembles their supported Pi, Codex, Claude, OpenCode, and
    # orchestrator surfaces without mutable npm installation.
    agent-intercom-pi-src = {
      url = "github:dataforxyz/agent-intercom-pi/b6f8f9d08c8c5ec7141a0258ce61cda59d327a20";
      flake = false;
    };
    agent-intercom-codex-src = {
      url = "github:dataforxyz/agent-intercom-codex/ea1c5b538c95b89af3fd36344396779e2eadbadb";
      flake = false;
    };
    agent-intercom-claude-src = {
      url = "github:dataforxyz/agent-intercom-claude/d62b3c85547b8b83fdfe06afb38968646fe813b8";
      flake = false;
    };
    agent-intercom-opencode-src = {
      url = "github:dataforxyz/agent-intercom-opencode/9d81100ea074f68f6466656c65536504209eb060";
      flake = false;
    };
    agent-intercom-orchestrator-src = {
      url = "github:dataforxyz/agent-intercom-orchestrator/a7e16bd4386726002ab6880b35ebacdeef00fd0d";
      flake = false;
    };
    agent-intercom-core-src = {
      url = "github:dataforxyz/agent-intercom-core/8316cbab548f422ad11c78ed887fabeef94817c1";
      flake = false;
    };
    # Pi extension packages. Kept as flake inputs so source revisions and
    # content hashes live in flake.lock, not in package Nix code.
    pi-linkup-src = {
      type = "file";
      url = "https://registry.npmjs.org/@aliou/pi-linkup/-/pi-linkup-0.11.0.tgz";
      flake = false;
    };
    pi-utils-ui-src = {
      type = "file";
      url = "https://registry.npmjs.org/@aliou/pi-utils-ui/-/pi-utils-ui-0.5.0.tgz";
      flake = false;
    };
    # Maintained reliability fork. Its ledger records the retained local
    # acceptance behavior and validation witnesses.
    pi-subagents-src = {
      url = "github:LiGoldragon/pi-subagents-nicobailon/bfca4f8317551fa9e8e8ef82c2608a6216953216";
      flake = false;
    };
    # Generated project-role packets used by the harness compatibility check.
    # The source revision itself pins skills at the authoritative generator revision.
    primary-generated-src = {
      url = "github:LiGoldragon/primary/fd049d9030a789ccb60e21732acdfc754b30e410";
      flake = false;
    };
    agent-intercom-tsx-src = {
      type = "file";
      url = "https://registry.npmjs.org/tsx/-/tsx-4.20.0.tgz";
      flake = false;
    };
    agent-intercom-typebox-src = {
      type = "file";
      url = "https://registry.npmjs.org/typebox/-/typebox-1.1.38.tgz";
      flake = false;
    };
    agent-intercom-esbuild-src = {
      type = "file";
      url = "https://registry.npmjs.org/esbuild/-/esbuild-0.25.0.tgz";
      flake = false;
    };
    agent-intercom-esbuild-linux-x64-src = {
      type = "file";
      url = "https://registry.npmjs.org/@esbuild/linux-x64/-/linux-x64-0.25.0.tgz";
      flake = false;
    };
    agent-intercom-esbuild-linux-arm64-src = {
      type = "file";
      url = "https://registry.npmjs.org/@esbuild/linux-arm64/-/linux-arm64-0.25.0.tgz";
      flake = false;
    };
    agent-intercom-get-tsconfig-src = {
      type = "file";
      url = "https://registry.npmjs.org/get-tsconfig/-/get-tsconfig-4.7.5.tgz";
      flake = false;
    };
    agent-intercom-resolve-pkg-maps-src = {
      type = "file";
      url = "https://registry.npmjs.org/resolve-pkg-maps/-/resolve-pkg-maps-1.0.0.tgz";
      flake = false;
    };
    pi-ultra-subagents-src = {
      type = "file";
      url = "https://registry.npmjs.org/pi-ultra-subagents/-/pi-ultra-subagents-0.1.0.tgz";
      flake = false;
    };
    pi-ultra-subagents-typebox-src = {
      type = "file";
      url = "https://registry.npmjs.org/typebox/-/typebox-1.1.38.tgz";
      flake = false;
    };
    pi-continue-src = {
      type = "file";
      url = "https://registry.npmjs.org/pi-continue/-/pi-continue-0.9.3.tgz";
      flake = false;
    };
    pi-session-namer.url = "github:LiGoldragon/pi-session-namer/76a145939d8fc52bda07117e7c04ad66f84f2114";
    pi-session-namer.inputs.nixpkgs.follows = "nixpkgs";
    pi-web-access-src = {
      type = "file";
      url = "https://registry.npmjs.org/pi-web-access/-/pi-web-access-0.13.0.tgz";
      flake = false;
    };
    pi-web-access-mixmark-io-domino-src = {
      type = "file";
      url = "https://registry.npmjs.org/@mixmark-io/domino/-/domino-2.2.0.tgz";
      flake = false;
    };
    pi-web-access-mozilla-readability-src = {
      type = "file";
      url = "https://registry.npmjs.org/@mozilla/readability/-/readability-0.6.0.tgz";
      flake = false;
    };
    pi-web-access-boolbase-src = {
      type = "file";
      url = "https://registry.npmjs.org/boolbase/-/boolbase-1.0.0.tgz";
      flake = false;
    };
    pi-web-access-css-select-src = {
      type = "file";
      url = "https://registry.npmjs.org/css-select/-/css-select-5.2.2.tgz";
      flake = false;
    };
    pi-web-access-css-what-src = {
      type = "file";
      url = "https://registry.npmjs.org/css-what/-/css-what-6.2.2.tgz";
      flake = false;
    };
    pi-web-access-cssom-src = {
      type = "file";
      url = "https://registry.npmjs.org/cssom/-/cssom-0.5.0.tgz";
      flake = false;
    };
    pi-web-access-dom-serializer-src = {
      type = "file";
      url = "https://registry.npmjs.org/dom-serializer/-/dom-serializer-2.0.0.tgz";
      flake = false;
    };
    pi-web-access-domelementtype-src = {
      type = "file";
      url = "https://registry.npmjs.org/domelementtype/-/domelementtype-2.3.0.tgz";
      flake = false;
    };
    pi-web-access-domhandler-src = {
      type = "file";
      url = "https://registry.npmjs.org/domhandler/-/domhandler-5.0.3.tgz";
      flake = false;
    };
    pi-web-access-domutils-src = {
      type = "file";
      url = "https://registry.npmjs.org/domutils/-/domutils-3.2.2.tgz";
      flake = false;
    };
    pi-web-access-entities-src = {
      type = "file";
      url = "https://registry.npmjs.org/entities/-/entities-4.5.0.tgz";
      flake = false;
    };
    pi-web-access-html-escaper-src = {
      type = "file";
      url = "https://registry.npmjs.org/html-escaper/-/html-escaper-3.0.3.tgz";
      flake = false;
    };
    pi-web-access-htmlparser2-src = {
      type = "file";
      url = "https://registry.npmjs.org/htmlparser2/-/htmlparser2-9.1.0.tgz";
      flake = false;
    };
    pi-web-access-linkedom-src = {
      type = "file";
      url = "https://registry.npmjs.org/linkedom/-/linkedom-0.16.11.tgz";
      flake = false;
    };
    pi-web-access-nth-check-src = {
      type = "file";
      url = "https://registry.npmjs.org/nth-check/-/nth-check-2.1.1.tgz";
      flake = false;
    };
    pi-web-access-p-limit-src = {
      type = "file";
      url = "https://registry.npmjs.org/p-limit/-/p-limit-6.2.0.tgz";
      flake = false;
    };
    pi-web-access-turndown-src = {
      type = "file";
      url = "https://registry.npmjs.org/turndown/-/turndown-7.2.4.tgz";
      flake = false;
    };
    pi-web-access-uhyphen-src = {
      type = "file";
      url = "https://registry.npmjs.org/uhyphen/-/uhyphen-0.2.0.tgz";
      flake = false;
    };
    pi-web-access-unpdf-src = {
      type = "file";
      url = "https://registry.npmjs.org/unpdf/-/unpdf-1.6.2.tgz";
      flake = false;
    };
    pi-web-access-yocto-queue-src = {
      type = "file";
      url = "https://registry.npmjs.org/yocto-queue/-/yocto-queue-1.2.2.tgz";
      flake = false;
    };

    # uv2nix toolchain — turns the uv.lock under packages/browser-use into
    # a pure-Nix Python environment. browser-use's dependency closure is
    # 264 packages (several missing from nixpkgs), so a lockfile-driven
    # build is mandatory; this is the maintained pyproject-nix path.
    # Fetched over git+https rather than the github: indirection so the
    # GitHub API rate-limit doesn't gate `nix flake lock`.
    pyproject-nix.url = "git+https://github.com/pyproject-nix/pyproject.nix";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";
    uv2nix.url = "git+https://github.com/pyproject-nix/uv2nix";
    uv2nix.inputs.pyproject-nix.follows = "pyproject-nix";
    uv2nix.inputs.nixpkgs.follows = "nixpkgs";
    pyproject-build-systems.url = "git+https://github.com/pyproject-nix/build-system-pkgs";
    pyproject-build-systems.inputs.pyproject-nix.follows = "pyproject-nix";
    pyproject-build-systems.inputs.uv2nix.follows = "uv2nix";
    pyproject-build-systems.inputs.nixpkgs.follows = "nixpkgs";

    # Emacs — replaces legacy pkdjz/mkEmacs. Planned split.
    #   criomos-emacs.url = "github:LiGoldragon/CriomOS-emacs";
    #   criomos-emacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      coreModule = bp.homeModules.default;
      horizon = inputs.horizon.horizon;
      lib = inputs.nixpkgs.lib;
      packageOverlays = [
        inputs.pkgs.inputs.nix-vscode-extensions.overlays.default
      ]
      ++ (import ./overlays { inherit inputs; });
      pkgs = inputs.pkgs.pkgs.extend (lib.composeManyExtensions packageOverlays);
      # Blueprint's default package set deliberately has no unfree policy.
      # Keep the producer's proprietary package allowance explicit and narrow:
      # only the four owned AI derivation names may pass package metadata
      # evaluation. This set is used only to construct the local package
      # outputs; it does not alter the profile-wide package policy.
      ownedUnfreeNames = [
        "claude-code"
        "claude-desktop"
        "chatgpt"
        "chatgpt-unwrapped"
      ];
      ownedUnfreePredicate = package: lib.elem (lib.getName package) ownedUnfreeNames;
      # Blueprint constructs its auto-imported package/check graph before it
      # hands control back to this flake. Give that functor the same narrow
      # policy used by the explicit Home outputs, so its four owned package
      # domains see the intended metadata without making unrelated unfree
      # packages available.
      bp = inputs.blueprint {
        inherit inputs;
        systems = [
          "x86_64-linux"
          "aarch64-linux"
        ];
        nixpkgs = {
          config.allowUnfreePredicate = ownedUnfreePredicate;
          overlays = packageOverlays;
        };
      };
      # Blueprint's `pkgs` is native to the current evaluation system.  Manual
      # checks for the other published systems must use the corresponding
      # CriomOS-pkgs universe (including its open-vsx overlay), then receive
      # Home's package overlays on top of that exact set.
      mkCriomOSPkgsForSystem =
        targetSystem:
        let
          criomOSPkgs = import "${inputs.pkgs}/flake.nix" {
            self = inputs.pkgs;
            nixpkgs = inputs.nixpkgs;
            system = {
              system = targetSystem;
            };
            nix-vscode-extensions = inputs.pkgs.inputs.nix-vscode-extensions;
          };
        in
        criomOSPkgs.pkgs.extend (lib.composeManyExtensions packageOverlays);
      checkPkgsForSystem =
        targetSystem:
        if targetSystem == pkgs.stdenv.hostPlatform.system then
          pkgs
        else
          mkCriomOSPkgsForSystem targetSystem;
      ownedPackagesForSystem =
        system:
        let
          ownedPkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfreePredicate = ownedUnfreePredicate;
            overlays = packageOverlays;
          };
          ownedAgentPackages = import ./lib/owned-agent-packages.nix {
            pkgs = ownedPkgs;
            inherit inputs;
            chatgptCommandLineArgs = "--ozone-platform=wayland";
          };
          basePackages = {
            codex = ownedAgentPackages.codexPackage;
            claude-code = ownedAgentPackages.claudeCodePackage;
          };
        in
        basePackages
        //
          lib.optionalAttrs (ownedAgentPackages ? chatgptPackage && ownedAgentPackages ? claudeDesktopPackage)
            {
              chatgpt = ownedAgentPackages.chatgptPackage;
              claude-desktop = ownedAgentPackages.claudeDesktopPackage;
            }
        // lib.optionalAttrs (lib.elem system agentIntercomSystems) {
          agent-intercom = ownedPkgs.callPackage ./packages/agent-intercom {
            inherit inputs;
            claudeCodePackage = ownedAgentPackages.claudeCodePackage;
            codexCliPackage = ownedAgentPackages.codexPackage;
          };
        };
      ownedPackageSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      agentIntercomSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      ownedCheckNames = [
        "agent-intercom"
        "desktop-app-support"
        "ai-agent-launch-orchestration"
        "claude-desktop-declared-cli"
        "claude-desktop-egl-linkage"
        "claude-desktop-launcher-linkage"
        "claude-remote-control"
        "codex-remote-control"
        "codex-remote-control-vm"
        "codex-tui"
      ];
      agentIntercomSupported = system: lib.elem system agentIntercomSystems;
      desktopAppSupported =
        system:
        let
          packages = ownedPackagesForSystem system;
        in
        packages ? chatgpt && packages ? claude-desktop;
      projectPackages = builtins.mapAttrs (
        system: packages:
        let
          systemPackages =
            if lib.elem system ownedPackageSystems then packages // ownedPackagesForSystem system else packages;
        in
        if agentIntercomSupported system then
          systemPackages
        else
          builtins.removeAttrs systemPackages [ "agent-intercom" ]
      ) bp.packages;
      blueprintGeneratedChecks =
        system:
        lib.mapAttrs' (packageName: package: {
          name = "pkgs-${packageName}";
          value = package;
        }) (projectPackages.${system} or { })
        // lib.mapAttrs' (devshellName: devshell: {
          name = "devshell-${devshellName}";
          value = devshell;
        }) (bp.devShells.${system} or { });
      packageCheckNames =
        system:
        builtins.listToAttrs (
          map (packageName: {
            name = "pkgs-${packageName}";
            value = true;
          }) (builtins.attrNames (projectPackages.${system} or { }))
        );
      # Blueprint imports every check before it can inspect platform metadata.
      # Select desktop-app checks from the actual owned package outputs rather
      # than a shared architecture predicate.
      derivationChecks = builtins.mapAttrs (
        _system: checks:
        if desktopAppSupported _system then
          lib.filterAttrs (
            name: value:
            lib.isDerivation value
            && (!lib.hasPrefix "pkgs-" name || builtins.hasAttr name (packageCheckNames _system))
          ) (builtins.removeAttrs checks ownedCheckNames)
        else
          blueprintGeneratedChecks _system
      ) (bp.checks or { });
      projectChecks = builtins.mapAttrs (
        _system: checks:
        let
          checkPkgs = checkPkgsForSystem _system;
        in
        checks
        // {
          chroma-datom-config = checkPkgs.callPackage ./checks/chroma-datom-config { inherit inputs; };
          chroma-emacs-resident = checkPkgs.callPackage ./checks/chroma-emacs-resident { inherit inputs; };
          default-opener = checkPkgs.callPackage ./checks/default-opener { inherit inputs; };
          listener-dictation-bindings = checkPkgs.callPackage ./checks/listener-dictation-bindings {
            inherit inputs;
          };
          listener-level-widget = checkPkgs.callPackage ./checks/listener-level-widget { };
          active-network-widget = checkPkgs.callPackage ./checks/active-network-widget { };
          solar-time-widget = checkPkgs.callPackage ./checks/solar-time-widget { };
          keyboard-layout-policy = checkPkgs.callPackage ./checks/keyboard-layout-policy { inherit inputs; };
          emacs-rust-analyzer-autostart = checkPkgs.callPackage ./checks/emacs-rust-analyzer-autostart { };
          editor-heavy-autostart = checkPkgs.callPackage ./checks/editor-heavy-autostart { };
          rust-toolchain = checkPkgs.callPackage ./checks/rust-toolchain { inherit inputs; };
          leta = checkPkgs.callPackage ./checks/leta { inherit inputs; };
          no-easyeffects = checkPkgs.callPackage ./checks/no-easyeffects { };
          ghostty-primary-selection = checkPkgs.callPackage ./checks/ghostty-primary-selection {
            inherit inputs;
          };
          bird-home-isolation = checkPkgs.callPackage ./checks/bird-home-isolation { inherit inputs; };
          desktop-shell-launch = checkPkgs.callPackage ./checks/desktop-shell-launch { inherit inputs; };
          wispr-flow-profile-tier = checkPkgs.callPackage ./checks/wispr-flow-profile-tier {
            inherit inputs;
          };
          wispr-status-niri-rule = checkPkgs.callPackage ./checks/wispr-status-niri-rule { inherit inputs; };
          noctalia-settings-composition = checkPkgs.callPackage ./checks/noctalia-settings-composition {
            inherit inputs;
          };
          nix-profile-compatibility = checkPkgs.callPackage ./checks/nix-profile-compatibility { };
          home-profile-absence = checkPkgs.callPackage ./checks/home-profile-absence {
            inherit inputs;
          };
          bitwarden-availability = checkPkgs.callPackage ./checks/bitwarden-availability { };
          dolthub-create-database = checkPkgs.callPackage ./checks/dolthub-create-database { };
          orchestrate-service-path = checkPkgs.callPackage ./checks/orchestrate-service-path {
            inherit inputs;
          };
          orchestrate-wrapper-fallback = checkPkgs.callPackage ./checks/orchestrate-wrapper-fallback {
            inherit inputs;
          };
          message-service-path = checkPkgs.callPackage ./checks/message-service-path { inherit inputs; };
          pi-criomos-package-load = checkPkgs.callPackage ./checks/pi-criomos-package-load {
            inherit inputs;
          };
          gws = checkPkgs.callPackage ./checks/gws { inherit inputs; };
          playwright-cli = checkPkgs.callPackage ./checks/playwright-cli { };
          spirit-deployment = checkPkgs.callPackage ./checks/spirit-deployment { inherit inputs; };
          flow-id = checkPkgs.callPackage ./checks/flow-id { inherit inputs; };
          aggregator-deployment = checkPkgs.callPackage ./checks/aggregator-deployment { inherit inputs; };
          vscodium-casual = checkPkgs.callPackage ./checks/vscodium-casual { };
          owned-agent-updater = checkPkgs.callPackage ./checks/owned-agent-updater { inherit inputs; };
          system-projection-boundary = checkPkgs.callPackage ./checks/system-projection-boundary { };
          main-contract-pins = checkPkgs.callPackage ./checks/main-contract-pins {
            inherit inputs;
          };
          codex-tui = checkPkgs.callPackage ./checks/codex-tui { };
          claude-remote-control = checkPkgs.callPackage ./checks/claude-remote-control {
            inherit inputs;
          };
          yt-dlp = checkPkgs.callPackage ./checks/yt-dlp {
            inherit inputs;
            homePkgs = checkPkgs;
          };
        }
        // lib.optionalAttrs (agentIntercomSupported _system) {
          agent-intercom = checkPkgs.callPackage ./checks/agent-intercom { inherit inputs; };
        }
        // lib.optionalAttrs (_system == "x86_64-linux") {
          vscodium-claude-lifecycle = checkPkgs.callPackage ./checks/vscodium-claude-lifecycle {
            inherit inputs;
          };
        }
        // lib.optionalAttrs (desktopAppSupported _system) {
          claude-desktop-declared-cli = checkPkgs.callPackage ./checks/claude-desktop-declared-cli {
            inherit inputs;
          };
          claude-desktop-launcher-linkage = checkPkgs.callPackage ./checks/claude-desktop-launcher-linkage {
            inherit inputs;
          };
          claude-desktop-egl-linkage = checkPkgs.callPackage ./checks/claude-desktop-egl-linkage {
            inherit inputs;
          };
          desktop-app-support = checkPkgs.callPackage ./checks/desktop-app-support {
            inherit inputs;
          };
        }
        // lib.optionalAttrs (_system == "x86_64-linux") {
          pi-harness-profile = checkPkgs.callPackage ./checks/pi-harness-profile { inherit inputs; };
          ai-agent-launch-orchestration = checkPkgs.callPackage ./checks/ai-agent-launch-orchestration {
            inherit inputs;
          };
          codex-remote-control = checkPkgs.callPackage ./checks/codex-remote-control {
            inherit inputs;
          };
          codex-remote-control-vm = checkPkgs.callPackage ./checks/codex-remote-control-vm {
            inherit inputs;
          };
        }
      ) derivationChecks;

      mkHomeConfiguration =
        userName: user:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit horizon user;
            ownedAgentPackages = import ./lib/owned-agent-packages.nix {
              inherit pkgs inputs;
              chatgptCommandLineArgs = "--ozone-platform=wayland";
            };
          };
          modules = [
            inputs.self.homeModules.default
            (
              { lib, ... }:
              {
                nixpkgs.overlays = lib.mkForce pkgs.overlays;
                home.username = userName;
                home.homeDirectory = "/home/${userName}";
                home.stateVersion = "26.05";
              }
            )
          ];
        };
    in
    bp
    // {
      packages = projectPackages;
      checks = projectChecks;
      apps = builtins.mapAttrs (system: _: bp.apps.${system} or { }) projectPackages;

      # Consumers need the exact overlay-applied package set without forcing a
      # standalone Home configuration.  A concrete user projection can supply
      # required per-user policy that the generic Home output deliberately
      # cannot know.
      legacyPackages.${pkgs.stdenv.hostPlatform.system} = pkgs;

      homeConfigurations = builtins.mapAttrs mkHomeConfiguration horizon.users;

      # Wrap blueprint's auto-discovered homeModules.default so that:
      # (1) upstream homeModules from CriomOS-home's own flake inputs
      #     (stylix, niri-flake, noctalia) are imported, exposing their
      #     option paths to the modules that consume them;
      # (2) the `inputs` arg seen inside our home modules is OUR flake's
      #     inputs, not whatever the consumer passed via extraSpecialArgs.
      # This is the architecture fix for the home-tcj wire-up — see
      # /home/li/git/CriomOS/reports/0019.
      homeModules.default =
        { lib, pkgs, ... }:
        {
          imports = [
            coreModule
            inputs.stylix.homeModules.stylix
            inputs.niri-flake.homeModules.config
            inputs.noctalia.homeModules.default
          ];
          # mkForce because the consumer (e.g. CriomOS userHomes.nix)
          # also passes its own `inputs` via extraSpecialArgs, which
          # would otherwise win the priority race.
          _module.args.inputs = lib.mkForce inputs;
          # Use nixpkgs niri (v26.04) instead of niri-flake's niri-stable
          # (v25.08).  niri-flake's niri-unstable in the current lock is
          # from July 2025 (pre-v26.04); nixpkgs already carries v26.04
          # which includes the DMA-buffer leak fix from PR #3404.
          programs.niri.package = lib.mkForce pkgs.niri;
          _module.args.criomos-lib = lib.mkForce inputs.criomos-lib.lib;
          _module.args.constants = lib.mkForce inputs.criomos-lib.lib.constants;
          _module.args.rustToolchain =
            lib.mkForce
              inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
          # Resolve the hexis binary once here so consumers don't repeat
          # `inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default`
          # at every call site.
          _module.args.hexis = lib.mkForce inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
          _module.args.ownedAgentPackages = lib.mkForce (
            import ./lib/owned-agent-packages.nix {
              inherit pkgs inputs;
              chatgptCommandLineArgs = "--ozone-platform=wayland";
            }
          );
        };
    };
}
