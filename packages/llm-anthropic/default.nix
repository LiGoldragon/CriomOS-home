{ pkgs, inputs, generationOnce ? false, includeCredentialAdapters ? false }:
assert includeCredentialAdapters -> generationOnce;
let
  python = pkgs.python314;
  workspace = inputs.uv2nix.lib.workspace.loadWorkspace { workspaceRoot = ./.; };
  upstream = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };
  generationPolicy = final: prev: pkgs.lib.optionalAttrs generationOnce {
    llm-anthropic = prev.llm-anthropic.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        cd "$out/${python.sitePackages}"
        patch --batch --forward -p1 < ${./generation-once.patch}
      '';
    });
  };
  pythonSet =
    (pkgs.callPackage inputs.pyproject-nix.build.packages { inherit python; }).overrideScope
      (pkgs.lib.composeManyExtensions [
        inputs.pyproject-build-systems.overlays.default
        upstream
        generationPolicy
      ]);
  venv = pythonSet.mkVirtualEnv "criomos-llm-anthropic-environment" workspace.deps.default;
in
pkgs.runCommand "llm-anthropic-0.38-0.31" {
  meta.mainProgram = "llm";
} (''
  mkdir -p "$out/bin"
  ln -s "${venv}/bin/llm" "$out/bin/llm"
'' + pkgs.lib.optionalString includeCredentialAdapters ''
  for procedure in opus-medium haiku-function-check; do
    command="$out/bin/llm-$procedure"
    printf '#!%s -IB\n' "${venv}/bin/python" > "$command"
    substitute ${./one-request.py} applied.py --replace-fail '@procedure@' "$procedure"
    cat applied.py >> "$command"
    chmod +x "$command"
  done
'')
