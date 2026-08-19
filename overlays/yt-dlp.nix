{ inputs }:
final: prev:
let
  versionFile = builtins.readFile "${inputs.yt-dlp}/yt_dlp/version.py";
  version = builtins.head (builtins.match ".*__version__ = '([^']+)'.*" versionFile);
in
{
  yt-dlp = prev.yt-dlp.overrideAttrs (_: {
    inherit version;
    src = inputs.yt-dlp;
  });
}
