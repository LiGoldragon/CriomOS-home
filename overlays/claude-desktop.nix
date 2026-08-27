{ inputs }:
final: prev: {
  claudeDesktopWithDeclaredClaudeCode =
    {
      claudeDesktopPackage,
      claudeCodePackage,
    }:
    prev.runCommand "claude-desktop-with-declared-claude-code-${claudeDesktopPackage.version}"
      {
        nativeBuildInputs = [
          prev.asar
          prev.nodejs
          prev.patchelf
        ];
        passthru.declaredClaudeCode = claudeCodePackage;
      }
      ''
        cp -a ${claudeDesktopPackage}/. "$out"
        chmod -R u+w "$out"
        app_asar="$out/lib/claude-desktop/resources/app.asar"
        extracted_app="$TMPDIR/app"
        ${prev.asar}/bin/asar extract "$app_asar" "$extracted_app"
        ${prev.nodejs}/bin/node ${./patch-claude-desktop-runtime.mjs} \
          "$extracted_app" \
          ${claudeCodePackage}/bin/claude
        rm "$app_asar"
        ${prev.asar}/bin/asar pack "$extracted_app" "$app_asar"
        substituteInPlace "$out/bin/claude-desktop" \
          --replace-fail "${claudeDesktopPackage}" "$out"
        patchelf --add-rpath ${prev.libglvnd}/lib \
          "$out/lib/claude-desktop/libGLESv2.so"
      '';
}
