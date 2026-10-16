{ pkgs, inputs, ... }:
let
  profile = pkgs.callPackage ../../packages/harness-profile { inherit inputs; };
  fakeCompiler = pkgs.writeShellScript "accounted-compiler" "exit 99";
  rustOnlyBaseline = pkgs.runCommand "rust-only-baseline" { } ''
    mkdir -p "$out/bin" "$out/share/applications" "$out/lib"
    ln -s ${fakeCompiler} "$out/bin/cargo"
    ln -s ${fakeCompiler} "$out/bin/rustc"
    ln -s ${pkgs.coreutils}/bin/true "$out/bin/flow"
    printf '%s\n' 'foreign desktop' > "$out/share/applications/foreign.desktop"
    printf '%s\n' 'unrelated resource' > "$out/lib/foreign"
  '';
  rustOnly = pkgs.callPackage ../../packages/harness-profile {
    inherit inputs;
    baseline = rustOnlyBaseline;
    rustOnly = true;
    ownedRustExports = {
      baseline = toString rustOnlyBaseline;
      exports = builtins.listToAttrs (
        map (name: {
          inherit name;
          value =
            if
              builtins.elem name [
                "cargo"
                "rustc"
              ]
            then
              {
                present = true;
                target = toString fakeCompiler;
              }
            else
              {
                present = false;
                target = null;
              };
        }) profile.rustCommands
      );
    };
  };
in
pkgs.runCommand "harness-home-profile-check"
  {
    nativeBuildInputs = [
      pkgs.coreutils
      pkgs.python3
    ];
  }
  ''
    # Rust-only mode preserves services, desktop resources and unrelated leaves.
    test "$(readlink -f ${rustOnly}/bin/flow)" = "$(readlink -f ${rustOnlyBaseline}/bin/flow)"
    test "$(readlink -f ${rustOnly}/share)" = "$(readlink -f ${rustOnlyBaseline}/share)"
    test "$(readlink -f ${rustOnly}/lib)" = "$(readlink -f ${rustOnlyBaseline}/lib)"
    test ! -e ${rustOnly}/bin/message
    test ! -e ${rustOnly}/bin/curriculum
    for name in ${pkgs.lib.concatStringsSep " " profile.rustCommands}; do
      test "$(readlink -f ${rustOnly}/bin/$name)" = "$(readlink -f ${profile.rust}/bin/$name)"
    done
    test "$(readlink -f ${profile}/bin/chatgpt)" = "$(readlink -f ${profile.chatgpt}/bin/chatgpt)"
    grep -qx 'Exec=chatgpt %U' ${profile}/share/applications/chatgpt.desktop
    grep -qx 'Icon=chatgpt' ${profile}/share/applications/chatgpt.desktop
    test -f ${profile}/share/pixmaps/chatgpt.png
    if grep -q '^TryExec=' ${profile}/share/applications/chatgpt.desktop; then
      grep -qx 'TryExec=chatgpt' ${profile}/share/applications/chatgpt.desktop
    fi
    for name in flow flow-meta flow-nexus; do
      test "$(readlink -f ${profile}/bin/$name)" = "$(readlink -f ${profile.flow}/bin/$name)"
    done
    for name in message message-meta message-nexus; do
      test "$(readlink -f ${profile}/bin/$name)" = "$(readlink -f ${profile.message}/bin/$name)"
    done
    for name in ${pkgs.lib.concatStringsSep " " profile.rustCommands}; do
      test "$(readlink -f ${profile}/bin/$name)" = "$(readlink -f ${profile.rust}/bin/$name)"
    done
    status=0
    ${profile}/bin/cargo test >reply 2>&1 || status=$?
    test "$status" -eq 126
    grep -F 'configured remote builder' reply
    for name in flow-next flow-next-meta message-next message-next-meta message-daemon meta-message; do
      test ! -e "${profile}/bin/$name"
    done
    for path in ${profile.baseline}/bin/*; do
      name=$(basename "$path")
      case "$name" in chatgpt|flow*|message*|meta-message|curriculum|messenger-clj|hm-*|${pkgs.lib.concatStringsSep "|" profile.rustCommands}) continue ;; esac
      test "$(readlink -f "$path")" = "$(readlink -f "${profile}/bin/$name")"
    done
    python - ${../../packages/harness-profile/merge-owned-share.py} ${profile.baseline}/share ${profile}/share ${profile.chatgpt}/share <<'PY'
    import importlib.util, pathlib, sys, tempfile
    spec = importlib.util.spec_from_file_location('merge', sys.argv[1])
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    baseline, output, package = map(pathlib.Path, sys.argv[2:])
    owned = {'applications/chatgpt.desktop', 'pixmaps/chatgpt.png'}
    for name, path in module.leaves(baseline).items():
        expected = package / name if name in owned else path
        assert (output / name).resolve() == expected.resolve(), name
    with tempfile.TemporaryDirectory() as directory:
        root = pathlib.Path(directory)
        base, old, new, result = [root / name for name in ('base', 'old', 'new', 'result')]
        for path in (base, old, new): path.mkdir()
        (old / 'old-only').write_text('old')
        (old / 'replace').write_text('old')
        (new / 'replace').write_text('new')
        (base / 'old-only').symlink_to(old / 'old-only')
        (base / 'replace').symlink_to(old / 'replace')
        (base / 'foreign').write_text('preserve')
        manifest = {'old': ['old-only', 'replace'], 'new': ['replace']}
        module.merge(base, old, new, result, manifest)
        assert not (result / 'old-only').exists()
        assert (result / 'foreign').resolve() == (base / 'foreign').resolve()
        assert (result / 'replace').resolve() == (new / 'replace').resolve()
        (base / 'replace').unlink()
        (base / 'replace').write_text('foreign collision')
        try: module.merge(base, old, new, root / 'refused', manifest)
        except ValueError as error: assert 'foreign share collision' in str(error)
        else: raise AssertionError('foreign collision accepted')
        assert not (root / 'refused').exists()
    PY
    mkdir -p "$out"
  ''
