{
  pkgs,
  inputs,
  baseline ? builtins.storePath "/nix/store/k6mwx3ys3sxava5ghys588ps97lblik5-home-manager-path",
  rustOnly ? false,
  ownedRustExports ? builtins.fromJSON (builtins.readFile ./owned-rust-exports.json),
  ...
}:
let
  # Exact accounted Ouranos baseline. Its other applications are preserved;
  # harness names come exclusively from the current Home source inputs.
  oldChatgpt = builtins.storePath "/nix/store/kds5yvpql0jkpbpq5j6ln8gxpybz5fnj-chatgpt-26.901.51231";
  chatgpt = (import ../../lib/owned-agent-packages.nix { inherit pkgs inputs; }).chatgptPackage;
  chatgptLeaves = [
    "applications/chatgpt.desktop"
    "pixmaps/chatgpt.png"
  ];
  chatgptManifest = builtins.toJSON {
    old = chatgptLeaves;
    new = chatgptLeaves;
  };
  flow = pkgs.callPackage ../flow-deployment { inherit inputs; };
  message = pkgs.callPackage ../message-deployment { inherit inputs; };
  curriculum = pkgs.callPackage ../curriculum-resolver-deployment { inherit inputs; };
  messenger = inputs.messenger-clj.packages.${pkgs.stdenv.hostPlatform.system}.default;
  rust = inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.rust-toolchain;
  rustCommands = rust.guardedCommands ++ [ "rustfmt" ];
  rustPattern = pkgs.lib.concatStringsSep "|" rustCommands;
  rustManifest = pkgs.writeText "owned-rust-exports.json" (builtins.toJSON ownedRustExports);
  replacementPackages =
    if rustOnly then
      [ rust ]
    else
      [
        flow
        message
        curriculum
        messenger
        chatgpt
        rust
      ];
  replacedHarnessPattern =
    if rustOnly then
      ""
    else
      "chatgpt|flow|flow-meta|flow-nexus|flow-next|flow-next-meta|message|message-meta|meta-message|message-nexus|message-daemon|message-write-configuration|message-next|message-next-meta|curriculum|messenger-clj|hm-*|";
in
pkgs.runCommand "harness-home-profile"
  {
    passthru = {
      inherit
        flow
        message
        curriculum
        messenger
        baseline
        chatgpt
        oldChatgpt
        chatgptLeaves
        rust
        rustCommands
        rustOnly
        ownedRustExports
        ;
    };
  }
  ''
    ${pkgs.python3}/bin/python - ${baseline} ${rustManifest} <<'PYTHON'
    import json, os, pathlib, sys
    baseline = pathlib.Path(sys.argv[1])
    manifest = json.loads(pathlib.Path(sys.argv[2]).read_text())
    if str(baseline) != manifest['baseline']:
        raise ValueError('Rust export manifest belongs to a different profile baseline')
    expected = manifest['exports']
    for name, entry in expected.items():
        path = baseline / 'bin' / name
        if os.path.lexists(path) != entry['present']:
            raise ValueError('Rust export presence changed: ' + name)
        if entry['present'] and os.path.realpath(path) != entry['target']:
            raise ValueError('Foreign Rust export target: ' + name)
    for path in (baseline / 'bin').iterdir():
        if path.name.startswith(('cargo', 'rust', 'clippy')) and path.name not in expected:
            raise ValueError('Unaccounted Rust export: ' + path.name)
    PYTHON
    mkdir -p "$out/bin"
    for path in ${baseline}/*; do
      name=$(basename "$path")
      case "$name" in bin) continue ;; share) ${if rustOnly then "true" else "continue"} ;; esac
      ln -s "$path" "$out/$name"
    done
    ${pkgs.lib.optionalString (!rustOnly) ''
      ${pkgs.python3}/bin/python ${./merge-owned-share.py} \
        ${baseline}/share ${oldChatgpt}/share ${chatgpt}/share "$out/share" \
        ${pkgs.lib.escapeShellArg chatgptManifest}
    ''}
    for path in ${baseline}/bin/*; do
      name=$(basename "$path")
      case "$name" in
        ${replacedHarnessPattern}${rustPattern}) continue ;;
      esac
      ln -s "$path" "$out/bin/$name"
    done
    for package in ${pkgs.lib.concatStringsSep " " (map toString replacementPackages)}; do
      for path in "$package/bin/"*; do
        name=$(basename "$path")
        test ! -e "$out/bin/$name"
        ln -s "$path" "$out/bin/$name"
      done
    done
  ''
