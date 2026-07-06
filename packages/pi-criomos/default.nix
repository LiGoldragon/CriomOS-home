{ pkgs, ... }:

pkgs.stdenvNoCC.mkDerivation {
  pname = "pi-criomos";
  version = "0.1.2";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    packageRoot=$out/share/pi-packages/pi-criomos
    mkdir -p \
      "$packageRoot/themes" \
      "$packageRoot/extensions" \
      "$packageRoot/skills/gws" \
      "$packageRoot/system"

    cat > "$packageRoot/package.json" <<'JSON'
    {
      "name": "pi-criomos",
      "version": "0.1.2",
      "keywords": ["pi-package"],
      "pi": {
        "themes": ["./themes"],
        "extensions": ["./extensions/live-theme-control.ts"],
        "skills": [
          "./skills"
        ]
      }
    }
    JSON

    install -m 0644 ${./skills/gws/SKILL.md} \
      "$packageRoot/skills/gws/SKILL.md"
    install -m 0644 ${./system/SYSTEM.md} \
      "$packageRoot/system/SYSTEM.md"
    install -m 0644 ${./extensions/live-theme-control.ts} \
      "$packageRoot/extensions/live-theme-control.ts"

    cat > "$packageRoot/themes/criomos-dark.json" <<'JSON'
    {
      "$schema": "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
      "name": "criomos-dark",
      "vars": {
        "accentBlue": "#7dd3fc",
        "accentGreen": "#86efac",
        "accentGold": "#facc15",
        "accentRed": "#fb7185",
        "surface": "#111827",
        "surfaceRaised": "#172033",
        "surfaceMuted": "#1f2937",
        "textSoft": "#d1d5db",
        "textMuted": "#9ca3af",
        "textDim": "#6b7280",
        "violet": "#c4b5fd",
        "cyan": "#67e8f9"
      },
      "colors": {
        "accent": "accentBlue",
        "border": "#38bdf8",
        "borderAccent": "cyan",
        "borderMuted": "#334155",
        "success": "accentGreen",
        "error": "accentRed",
        "warning": "accentGold",
        "muted": "textMuted",
        "dim": "textDim",
        "text": "textSoft",
        "thinkingText": "#a5b4fc",
        "selectedBg": "surfaceMuted",
        "userMessageBg": "surfaceRaised",
        "userMessageText": "#f9fafb",
        "customMessageBg": "surfaceRaised",
        "customMessageText": "textSoft",
        "customMessageLabel": "accentBlue",
        "toolPendingBg": "#1e293b",
        "toolSuccessBg": "#102a20",
        "toolErrorBg": "#2a1420",
        "toolTitle": "accentBlue",
        "toolOutput": "#e5e7eb",
        "mdHeading": "accentGold",
        "mdLink": "accentBlue",
        "mdLinkUrl": "textMuted",
        "mdCode": "cyan",
        "mdCodeBlock": "#e5e7eb",
        "mdCodeBlockBorder": "#475569",
        "mdQuote": "textMuted",
        "mdQuoteBorder": "#475569",
        "mdHr": "#334155",
        "mdListBullet": "cyan",
        "toolDiffAdded": "#86efac",
        "toolDiffRemoved": "#fb7185",
        "toolDiffContext": "textMuted",
        "syntaxComment": "textDim",
        "syntaxKeyword": "violet",
        "syntaxFunction": "accentBlue",
        "syntaxVariable": "#fbbf24",
        "syntaxString": "#86efac",
        "syntaxNumber": "#f0abfc",
        "syntaxType": "cyan",
        "syntaxOperator": "#e5e7eb",
        "syntaxPunctuation": "textMuted",
        "thinkingOff": "textDim",
        "thinkingMinimal": "accentBlue",
        "thinkingLow": "cyan",
        "thinkingMedium": "accentGreen",
        "thinkingHigh": "accentGold",
        "thinkingXhigh": "accentRed",
        "bashMode": "#f59e0b"
      }
    }
    JSON

    cat > "$packageRoot/themes/criomos-light.json" <<'JSON'
    {
      "$schema": "https://raw.githubusercontent.com/earendil-works/pi/main/packages/coding-agent/src/modes/interactive/theme/theme-schema.json",
      "name": "criomos-light",
      "vars": {
        "accentBlue": "#0369a1",
        "accentGreen": "#15803d",
        "accentGold": "#a16207",
        "accentRed": "#be123c",
        "surface": "#f8fafc",
        "surfaceRaised": "#e0f2fe",
        "surfaceMuted": "#e2e8f0",
        "textSoft": "#111827",
        "textMuted": "#475569",
        "textDim": "#64748b",
        "violet": "#6d28d9",
        "cyan": "#0e7490"
      },
      "colors": {
        "accent": "accentBlue",
        "border": "#0284c7",
        "borderAccent": "cyan",
        "borderMuted": "#94a3b8",
        "success": "accentGreen",
        "error": "accentRed",
        "warning": "accentGold",
        "muted": "textMuted",
        "dim": "textDim",
        "text": "textSoft",
        "thinkingText": "#3730a3",
        "selectedBg": "surfaceMuted",
        "userMessageBg": "surfaceRaised",
        "userMessageText": "#0f172a",
        "customMessageBg": "surfaceRaised",
        "customMessageText": "textSoft",
        "customMessageLabel": "accentBlue",
        "toolPendingBg": "#e0f2fe",
        "toolSuccessBg": "#dcfce7",
        "toolErrorBg": "#ffe4e6",
        "toolTitle": "accentBlue",
        "toolOutput": "#111827",
        "mdHeading": "accentGold",
        "mdLink": "accentBlue",
        "mdLinkUrl": "textMuted",
        "mdCode": "cyan",
        "mdCodeBlock": "#111827",
        "mdCodeBlockBorder": "#94a3b8",
        "mdQuote": "textMuted",
        "mdQuoteBorder": "#94a3b8",
        "mdHr": "#cbd5e1",
        "mdListBullet": "cyan",
        "toolDiffAdded": "#15803d",
        "toolDiffRemoved": "#be123c",
        "toolDiffContext": "textMuted",
        "syntaxComment": "textDim",
        "syntaxKeyword": "violet",
        "syntaxFunction": "accentBlue",
        "syntaxVariable": "#92400e",
        "syntaxString": "#15803d",
        "syntaxNumber": "#a21caf",
        "syntaxType": "cyan",
        "syntaxOperator": "#111827",
        "syntaxPunctuation": "textMuted",
        "thinkingOff": "textDim",
        "thinkingMinimal": "accentBlue",
        "thinkingLow": "cyan",
        "thinkingMedium": "accentGreen",
        "thinkingHigh": "accentGold",
        "thinkingXhigh": "accentRed",
        "bashMode": "#b45309"
      }
    }
    JSON

    runHook postInstall
  '';

  meta = {
    description = "CriomOS Pi prompt, skills, themes, and live theme-control extension";
    license = pkgs.lib.licenses.mit;
  };
}
