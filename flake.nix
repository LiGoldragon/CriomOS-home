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

    horizon.url = "path:./stubs/no-horizon";

    # Compositor + shell.
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:noctalia-dev/noctalia-shell";
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
      url = "https://open-vsx.org/api/Anthropic/claude-code/linux-x64/2.1.185/file/Anthropic.claude-code-2.1.185@linux-x64.vsix";
      flake = false;
    };

    # `substack` CLI — its own flake, exposes packages.<system>.default.
    substack-cli.url = "github:LiGoldragon/substack-cli";
    substack-cli.inputs.nixpkgs.follows = "nixpkgs";

    # `whisrs` — Linux/Niri dictation tool. Consumed from the CriomOS fork,
    # which carries our daily dictation safety, recovery, status-bar, and
    # recall integration patches on the `criomos` branch.
    whisrs-src = {
      url = "github:LiGoldragon/whisrs?ref=criomos";
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

    # AI coding agents (daily auto-updates) — Li uses claude-code +
    # codex 12h/day, regression dropped them in the 2026-04-25 trim.
    # llm-agents keeps its own nixpkgs: its package set follows fast
    # tool packaging and currently needs newer pnpm attributes than the
    # profile-wide nixpkgs pin provides.
    llm-agents.url = "github:numtide/llm-agents.nix";
    codex-cli.url = "github:sadjow/codex-cli-nix";
    codex-cli.inputs.nixpkgs.follows = "nixpkgs";

    # Google Workspace CLI for no-MCP assistant access to Gmail, Drive,
    # Calendar, Docs, Sheets, Slides, Tasks, and People/Contacts.
    google-workspace-cli.url = "github:googleworkspace/cli";
    google-workspace-cli.inputs.nixpkgs.follows = "nixpkgs";

    # CriomOS deploy CLI. This is the Nota-first deploy tool used for
    # system, OS-only, and direct home deployments.
    lojix.url = "github:LiGoldragon/lojix";
    lojix.inputs.nixpkgs.follows = "nixpkgs";

    # Chroma — unified visual-state daemon (theme + warmth + brightness).
    # Replaces darkman + the nightshift-* services + the brightness shell
    # wrapper. Consumed in modules/home/profiles/min/chroma.nix.
    chroma.url = "github:LiGoldragon/chroma";
    chroma.inputs.nixpkgs.follows = "nixpkgs";

    # Spirit — schema-derived psyche record command line and user-session daemon.
    # Consumed in modules/home/profiles/min/spirit.nix.
    spirit.url = "github:LiGoldragon/spirit";
    spirit.inputs.nixpkgs.follows = "nixpkgs";

    # Agent — local OpenAI-compatible provider daemon used by Spirit's guardian.
    # Consumed in modules/home/profiles/min/spirit.nix.
    agent.url = "github:LiGoldragon/agent";
    agent.inputs.nixpkgs.follows = "nixpkgs";
    agent.inputs.crane.follows = "crane";

    # Mentci — psyche-facing approval daemon and egui client surface.
    # The daemon repo is packaged locally because it does not expose a flake;
    # mentci-egui exposes the GUI and its remote-control helper binaries.
    mentci-src = {
      url = "github:LiGoldragon/mentci";
      flake = false;
    };
    mentci-egui.url = "github:LiGoldragon/mentci-egui";
    mentci-egui.inputs.nixpkgs.follows = "nixpkgs";

    # `pi` (earendil-works/pi coding-agent CLI) — TypeScript npm
    # monorepo with no upstream flake. Consumed as a non-flake source
    # input and built locally via `packages/pi/default.nix`
    # (buildNpmPackage over the `packages/coding-agent` workspace).
    # Replaces the previous pi-mentci wrapper flake (dropped 2026-04-25).
    pi-src = {
      url = "github:earendil-works/pi?ref=v0.80.2";
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
    pi-subagents-src = {
      type = "file";
      url = "https://registry.npmjs.org/pi-subagents/-/pi-subagents-0.31.0.tgz";
      flake = false;
    };
    pi-continue-src = {
      type = "file";
      url = "https://registry.npmjs.org/pi-continue/-/pi-continue-0.8.2.tgz";
      flake = false;
    };
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
      bp = inputs.blueprint { inherit inputs; };
      coreModule = bp.homeModules.default;
      horizon = inputs.horizon.horizon;
      pkgs = inputs.pkgs.pkgs;
      lib = inputs.nixpkgs.lib;
      packageCheckNames =
        system:
        builtins.listToAttrs (
          map (packageName: {
            name = "pkgs-${packageName}";
            value = true;
          }) (builtins.attrNames (bp.packages.${system} or { }))
        );
      derivationChecks = builtins.mapAttrs (
        _system: checks:
        lib.filterAttrs (
          name: value:
          lib.isDerivation value
          && (!lib.hasPrefix "pkgs-" name || builtins.hasAttr name (packageCheckNames _system))
        ) checks
      ) (bp.checks or { });
      projectChecks = builtins.mapAttrs (
        _system: checks:
        let
          checkPkgs = import inputs.nixpkgs { system = _system; };
        in
        checks
        // {
          chroma-nota-config = checkPkgs.callPackage ./checks/chroma-nota-config { inherit inputs; };
          whisrs-dictation-bindings = checkPkgs.callPackage ./checks/whisrs-dictation-bindings {
            inherit inputs;
          };
          whisrs-default-input = checkPkgs.callPackage ./checks/whisrs-default-input { inherit inputs; };
          whisrs-recall = checkPkgs.callPackage ./checks/whisrs-recall { inherit inputs; };
          whisrs-level-widget = checkPkgs.callPackage ./checks/whisrs-level-widget { };
          rust-toolchain = checkPkgs.callPackage ./checks/rust-toolchain { inherit inputs; };
          leta = checkPkgs.callPackage ./checks/leta { inherit inputs; };
          no-easyeffects = checkPkgs.callPackage ./checks/no-easyeffects { };
          pi-harness-profile = checkPkgs.callPackage ./checks/pi-harness-profile { inherit inputs; };
          pi-criomos-extension-load = checkPkgs.callPackage ./checks/pi-criomos-extension-load {
            inherit inputs;
          };
          gws = checkPkgs.callPackage ./checks/gws { inherit inputs; };
          playwright-cli = checkPkgs.callPackage ./checks/playwright-cli { };
          lojix-run = checkPkgs.callPackage ./checks/lojix-run { inherit inputs; };
          spirit-deployment = checkPkgs.callPackage ./checks/spirit-deployment { inherit inputs; };
          vscodium-casual = checkPkgs.callPackage ./checks/vscodium-casual { };
        }
      ) derivationChecks;

      mkHomeConfiguration =
        userName: user:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit horizon user;
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
      checks = projectChecks;

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
          _module.args.criomos-lib = lib.mkForce inputs.criomos-lib.lib;
          _module.args.constants = lib.mkForce inputs.criomos-lib.lib.constants;
          _module.args.rustToolchain =
            lib.mkForce
              inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
          # Resolve the hexis binary once here so consumers don't repeat
          # `inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default`
          # at every call site.
          _module.args.hexis = lib.mkForce inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    };
}
