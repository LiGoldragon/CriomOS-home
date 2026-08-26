{ inputs }:
final: prev:
{
  claudeDesktopWithDeclaredClaudeCode =
    {
      claudeDesktopPackage,
      claudeCodePackage,
    }:
    prev.runCommand "claude-desktop-with-declared-claude-code-${claudeDesktopPackage.version}"
      {
        nativeBuildInputs = [
          prev.asar
          prev.makeWrapper
          prev.nodejs
        ];
        passthru.declaredClaudeCode = claudeCodePackage;
      }
      ''
        cp -a ${claudeDesktopPackage}/. "$out"
        app_asar="$out/lib/claude-desktop/resources/app.asar"
        extracted_app="$TMPDIR/app"
        chmod u+w "$out/lib/claude-desktop/resources" "$app_asar"
        ${prev.asar}/bin/asar extract "$app_asar" "$extracted_app"
        ${prev.nodejs}/bin/node ${./patch-claude-desktop-runtime.mjs} \
          "$extracted_app" \
          ${claudeCodePackage}/bin/claude
        rm "$app_asar"
        ${prev.asar}/bin/asar pack "$extracted_app" "$app_asar"
        wrapProgram "$out/bin/claude-desktop" \
          --set CLAUDE_CODE_LOCAL_BINARY ${claudeCodePackage}/bin/claude
      '';
}
