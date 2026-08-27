{
  pkgs,
  chatgptPackage,
  codexDesktopGate,
}:
chatgptPackage.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
    pkgs.findutils
    pkgs.coreutils
  ];
  postFixup = (old.postFixup or "") + ''
    resources_codex="$(find "$out" -type f -path '*/resources/codex' -print -quit)"
    test -n "$resources_codex"
    test "$(find "$out" -type f -path '*/resources/codex' | wc -l)" = 1
    rm "$resources_codex"
    ln -s ${codexDesktopGate}/bin/codex "$resources_codex"
  '';
})
