{
  pkgs,
  inputs ? null,
  codexPackage ? pkgs.callPackage ../owned-agents/codex { inherit inputs; },
  claudeCodePackage ? pkgs.callPackage ../owned-agents/claude-code { inherit inputs; },
  chatgptCommandLineArgs ? "--ozone-platform=wayland",
}:

let
  codexDesktopGate = pkgs.callPackage ../owned-agents/codex/desktop-gate.nix {
    codexCliPackage = codexPackage;
  };
in
{
  inherit codexPackage claudeCodePackage;
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  chatgptPackage = pkgs.callPackage ../owned-agents/chatgpt {
    inherit codexPackage codexDesktopGate;
    commandLineArgs = chatgptCommandLineArgs;
  };
  claudeDesktopPackage = pkgs.callPackage ../owned-agents/claude-desktop {
    inherit claudeCodePackage;
  };
}
