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

    # Editor — vscodium extensions, llm agent tooling.
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";
    llm-agents.url = "github:numtide/llm-agents.nix";
    llm-agents.inputs.nixpkgs.follows = "nixpkgs";

    # Mentci workspace.
    mentci-tools.url = "github:LiGoldragon/mentci-tools";
    mentci-tools.inputs.nixpkgs.follows = "nixpkgs";
    pi-mentci.url = "github:LiGoldragon/pi-mentci";
    pi-mentci.inputs.nixpkgs.follows = "nixpkgs";

    # Emacs — replaces legacy pkdjz/mkEmacs. Planned split.
    #   criomos-emacs.url = "github:LiGoldragon/CriomOS-emacs";
    #   criomos-emacs.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs: inputs.blueprint { inherit inputs; };
}
