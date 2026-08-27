# Validate updater recipes at evaluation time.
{ lib }:
let
  requiredByKind = {
    platform = [
      "versionSource"
      "urlTemplate"
      "platforms"
    ];
    manifest-checksums = [
      "versionSource"
      "manifestUrl"
      "checksumPath"
      "platforms"
    ];
    script = [ "script" ];
  };
in
config:
let
  kind = config.kind or (throw "passthru.updater: missing required attribute 'kind'");
  required = requiredByKind.${kind} or (throw "passthru.updater: unknown kind '${kind}'");
  missing = lib.filter (field: !(config ? ${field})) required;
in
if missing != [ ] then
  throw "passthru.updater (kind '${kind}'): missing ${lib.concatStringsSep ", " missing}"
else
  config
