{ inputs, pkgs, ... }:

let
  version = "2.1.231";
  system = pkgs.stdenv.hostPlatform.system;
  platform = {
    x86_64-linux = "linux-x64";
    aarch64-linux = "linux-arm64";
    aarch64-darwin = "darwin-arm64";
  }.${system} or (throw "Unsupported Claude Code platform: ${system}");
  hashes = {
    x86_64-linux = "sha256-R6Adrr95T2yGwT0Yda1uW+BicCmthgBzEWHyQBjs3ls=";
    aarch64-linux = "sha256-TufEhLEd7OZSGqIXOhnqkTQowceFmRhtYlWdLSrvTjI=";
    aarch64-darwin = "sha256-unkCecq273e3E4ZNS/X3ZPzqh9Oj63WRpB90HkUhK1w=";
  };
in
# llm-agents has not yet packaged the vendor 2.1.231 release.  Override only
# its source/version so its supported wrapper remains authoritative: Linux
# keeps wrapBuddy and the bubblewrap+socat PATH closure, and the upstream
# disableTelemetry option remains available to consumers.
(inputs.llm-agents.packages.${system}.claude-code.overrideAttrs (_: {
  inherit version;
  src = pkgs.fetchurl {
    url = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases/${version}/${platform}/claude";
    hash = hashes.${system};
  };
}))
