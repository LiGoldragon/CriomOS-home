{
  description = "CriomOS-home — home profile. Standalone home-manager flake consumed by CriomOS.";

  inputs = {
    nixpkgs.url = "github:LiGoldragon/nixpkgs?ref=main";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    crane.url = "github:ipetkov/crane";

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
      url = "https://open-vsx.org/api/anthropic/claude-code/linux-x64/2.1.126/file/anthropic.claude-code-2.1.126@linux-x64.vsix";
      flake = false;
    };

    # `gc` (Gas City) — multi-agent orchestration SDK. Consumes our
    # nix packaging flake which builds upstream gastownhall/gascity
    # via buildGo125Module. `bd` itself comes from nixpkgs.
    gascity.url = "github:LiGoldragon/gascity-nix";
    gascity.inputs.nixpkgs.follows = "nixpkgs";

    # Criopolis cascade dispatcher daemon.
    orchestrator.url = "github:LiGoldragon/orchestrator";
    orchestrator.inputs.nixpkgs.follows = "nixpkgs";
    orchestrator.inputs.gascity-nix.follows = "gascity";

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
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";
    codex-cli.url = "github:sadjow/codex-cli-nix";
    codex-cli.inputs.nixpkgs.follows = "nixpkgs";

    # CriomOS deploy CLI. This is the Nota-first deploy tool used for
    # system, OS-only, and direct home deployments.
    lojix-cli.url = "github:LiGoldragon/lojix-cli";
    lojix-cli.inputs.nixpkgs.follows = "nixpkgs";

    # Chroma — unified visual-state daemon (theme + warmth + brightness).
    # Replaces darkman + the nightshift-* services + the brightness shell
    # wrapper. Consumed in modules/home/profiles/min/chroma.nix.
    chroma.url = "github:LiGoldragon/chroma";
    chroma.inputs.nixpkgs.follows = "nixpkgs";

    # `pi` (badlogic/pi-mono coding-agent CLI) — TypeScript npm
    # monorepo with no upstream flake. Consumed as a non-flake source
    # input and built locally via `packages/pi/default.nix`
    # (buildNpmPackage over the `packages/coding-agent` workspace).
    # Replaces the previous pi-mentci wrapper flake (dropped 2026-04-25).
    pi-src = {
      url = "github:badlogic/pi-mono?ref=v0.72.1";
      flake = false;
    };

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
          whisrs-recall = checkPkgs.callPackage ./checks/whisrs-recall { inherit inputs; };
          whisrs-level-widget = checkPkgs.callPackage ./checks/whisrs-level-widget { };
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
          # Resolve the hexis binary once here so consumers don't repeat
          # `inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default`
          # at every call site.
          _module.args.hexis = lib.mkForce inputs.hexis.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    };
}
