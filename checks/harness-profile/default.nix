{ pkgs, inputs, ... }:
let
  profile = pkgs.callPackage ../../packages/harness-profile { inherit inputs; };
in
pkgs.runCommand "harness-home-profile-check" { nativeBuildInputs = [ pkgs.coreutils pkgs.python3 ]; } ''
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
  for name in flow-next flow-next-meta message-next message-next-meta message-daemon meta-message; do
    test ! -e "${profile}/bin/$name"
  done
  for path in ${profile.baseline}/bin/*; do
    name=$(basename "$path")
    case "$name" in chatgpt|flow*|message*|meta-message|curriculum|messenger-clj|hm-*) continue ;; esac
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
