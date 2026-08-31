{
  pkgs,
  inputs ? null,
  codexPackage ? pkgs.callPackage ../owned-agents/codex { inherit inputs; },
  claudeCodePackage ? pkgs.callPackage ../owned-agents/claude-code { inherit inputs; },
  chatgptCommandLineArgs ? "--ozone-platform=wayland",
}:

{
  inherit codexPackage claudeCodePackage;
}
// pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
  chatgptPackage = pkgs.callPackage ../owned-agents/chatgpt {
    inherit codexPackage;
    commandLineArgs = chatgptCommandLineArgs;
  };
  claudeDesktopPackage = pkgs.callPackage ../owned-agents/claude-desktop {
    inherit claudeCodePackage;
  };
}
