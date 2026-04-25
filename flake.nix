{
  description = "CriomOS-home — home profile. Standalone home-manager flake consumed by CriomOS.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs?ref=nixos-unstable";

    blueprint.url = "github:numtide/blueprint";
    blueprint.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Compositor + shell.
    niri-flake.url = "github:sodiboo/niri-flake";
    niri-flake.inputs.nixpkgs.follows = "nixpkgs";
    noctalia.url = "github:noctalia-dev/noctalia-shell";
    noctalia.inputs.nixpkgs.follows = "nixpkgs";

    # Styling.
    stylix.url = "github:danth/stylix";
    stylix.inputs.nixpkgs.follows = "nixpkgs";

    # Editor — vscodium extensions.
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";

    # Mentci workspace.
    mentci-tools.url = "github:LiGoldragon/mentci-tools";
    mentci-tools.inputs.nixpkgs.follows = "nixpkgs";

    # Emacs — replaces legacy pkdjz/mkEmacs. Planned split.
    #   criomos-emacs.url = "github:LiGoldragon/CriomOS-emacs";
    #   criomos-emacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs:
    let
      bp = inputs.blueprint { inherit inputs; };
      coreModule = bp.homeModules.default;
    in
    bp
    // {
      # Wrap blueprint's auto-discovered homeModules.default so that:
      # (1) upstream homeModules from CriomOS-home's own flake inputs
      #     (stylix, niri-flake, noctalia) are imported, exposing their
      #     option paths to the modules that consume them;
      # (2) the `inputs` arg seen inside our home modules is OUR flake's
      #     inputs, not whatever the consumer passed via extraSpecialArgs.
      # This is the architecture fix for the home-tcj wire-up — see
      # /home/li/git/CriomOS/reports/0019.
      homeModules.default = { lib, ... }: {
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
      };
    };
}
