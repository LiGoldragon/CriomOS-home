{
  pkgs,
  inputs,
  ...
}:
# browser-use — the popular LLM-driven browser agent
# (github.com/browser-use/browser-use). Packaged as a pure-Nix Python
# environment via uv2nix over the pinned uv.lock in this directory (264
# transitive packages, the closure is large — gated to the Large tier
# alongside Chrome by the consuming module). browser-use drives a real
# Chrome over the Chrome DevTools Protocol and reads the page visually
# with a vision model; CriomOS points that vision model at the
# workspace-local Gemma 4 on prometheus, never a cloud API (Spirit
# u275/wvgh/8pgh). The local-endpoint + gopass-token wiring lives in
# modules/home/profiles/max/browser-use.nix; this package only produces
# the environment and puts the `browser-use`/`bu` CLI on PATH (Spirit
# bxe9: packaged and on PATH, any harness calls it like a shell command).
let
  inherit (pkgs) lib;
  python = pkgs.python313;

  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };

  # Wheel preference keeps uv2nix from attempting source builds across
  # the large LLM-SDK dependency tree.
  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages { inherit python; }).overrideScope (
      lib.composeManyExtensions [
        inputs.pyproject-build-systems.overlays.default
        overlay
      ]
    );

  venv = pythonSet.mkVirtualEnv "criomos-browser-use-env" workspace.deps.default;
in
# The virtual env exposes the browser-use console scripts (browser-use,
# bu, browseruse, browser-use-tui) and the env's python (bin/python) for
# library-mode driver scripts. mainProgram points at the CLI so
# `lib.getExe` resolves it.
venv.overrideAttrs (old: {
  meta = (old.meta or { }) // {
    mainProgram = "browser-use";
    description = "LLM-driven browser agent (local-Gemma-vision-driven on CriomOS)";
    homepage = "https://github.com/browser-use/browser-use";
  };
})
