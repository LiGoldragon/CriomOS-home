{
  home = "/home/li/.codex-plain-i6q2ban20b4h";
  hostPublicKey = "/etc/ssh/ssh_host_ed25519_key.pub";
  hostPublicKeyDigest = "0a835951731daad8c3c627ad3fd83af5b55835d67252617240ba151095a17b22";
  target = "legacy";
  handlers = {
    SessionStart = {
      event = "session_start";
      legacy = "sha256:efca92cd2b8d8366df716849aa474e7a284a05a2b71ae0c1d34b903eb3fc6258";
      immutable = "sha256:632f15db4354c2bf8af3dd934037ab809da4e9e6595ce6c9163384f920618489";
    };
    PermissionRequest = {
      event = "permission_request";
      legacy = "sha256:0a69b7f72ba9d38db2fa53b1ea05032d41a00bb5f33426db73ce4ee30300794e";
      immutable = "sha256:1ed60bc75ca1ec445bf421235a334a6f65a21375d6168e5ce80da697530c06bb";
    };
    PostToolUse = {
      event = "post_tool_use";
      legacy = "sha256:177afdb3817c6214a8e435c8985c49fe76cf2335db4001251be72106d6fcfc59";
      immutable = "sha256:084678396a6f072291f4653412c142445886c4a61f9041606c6863b1b5694ca4";
    };
    PostCompact = {
      event = "post_compact";
      legacy = "sha256:3ae2b39ccccdc66ba3c06bb94362c72d835da775cbfd1abee35b15b5593b7b40";
      immutable = "sha256:182f1d9461865116fa5eb3e98373e24597cc34a35b3fbcfa763954ad0e2224d0";
    };
  };
}
