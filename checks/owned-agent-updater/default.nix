{ pkgs, ... }:

pkgs.runCommand "owned-agent-updater-negative-path"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.gnupg
    ];
  }
  ''
    set -eu
    export PYTHONPATH=${../../scripts}
    python3 - <<'PY'
    import importlib.util
    import json
    import tempfile
    from pathlib import Path
    from types import SimpleNamespace

    import owned_ai_updater as shared


    def load(name, path):
        spec = importlib.util.spec_from_file_location(name, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module


    chatgpt = load("chatgpt_updater", "${../../owned-agents/chatgpt/update.py}")
    codex = load("codex_updater", "${../../owned-agents/codex/update.py}")
    claude_desktop = load("claude_desktop_updater", "${../../owned-agents/claude-desktop/update.py}")
    chatgpt_key = Path("${../../owned-agents/chatgpt/openai-archive-key.asc}")


    def must_fail(function):
        try:
            function()
        except Exception:
            return
        raise AssertionError("negative-path operation unexpectedly succeeded")


    # Signed package indexes reject both wrong lengths and wrong digests without
    # contacting either repository.
    must_fail(lambda: chatgpt.verify_index(b"bad", "0" * 64, 4))
    must_fail(lambda: chatgpt.verify_index(b"bad", "0" * 64, 3))
    must_fail(lambda: claude_desktop.verify_index(b"bad", "0" * 64, 3, "amd64"))

    # A changed archive key and an unsigned Release are terminal trust errors;
    # this uses only the vendored key and local bytes.
    must_fail(lambda: shared.verify_key_fingerprint(
        "${pkgs.gnupg}/bin/gpg", chatgpt_key, "0" * 40
    ))
    must_fail(lambda: chatgpt.signed_release(
        b"not an OpenPGP clear-signed release", chatgpt_key,
        "${pkgs.gnupg}/bin/gpg", "${pkgs.gnupg}/bin/gpgv"
    ))

    # Codex follows the latest stable upstream release rather than moving a
    # declarative profile onto a vendor prerelease channel.
    original_fetch_json = codex.fetch_json
    codex.fetch_json = lambda _url: [
        {"tag_name": "rust-v0.152.0-alpha.5", "prerelease": True},
        {"tag_name": "rust-v0.151.0"},
    ]
    try:
        assert codex.latest_version() == "0.151.0"
    finally:
        codex.fetch_json = original_fetch_json

    assert claude_desktop.same_release_content(b"release", b"release\n")
    assert not claude_desktop.same_release_content(b"release-a", b"release-b\n")

    with tempfile.TemporaryDirectory(prefix="owned-agent-updater-check-") as directory:
        root = Path(directory)
        hashes = root / "hashes.json"
        hashes.write_text('{"cargoHash":"old"}\n', encoding="utf-8")

        # A failed atomic replace leaves the checked-in file and no temporary
        # sibling behind.
        original_replace = shared.os.replace

        def fail_replace(source, destination):
            raise OSError("injected replace failure")

        shared.os.replace = fail_replace
        must_fail(lambda: shared.atomic_write_text(hashes, '{"cargoHash":"new"}\n'))
        shared.os.replace = original_replace
        assert hashes.read_text(encoding="utf-8") == '{"cargoHash":"old"}\n'
        assert not list(root.glob(".hashes.json.*.tmp"))

        # The Codex dependency probe restores the original JSON when Nix does
        # not return a valid replacement hash.
        def failed_probe(*args, **kwargs):
            return SimpleNamespace(returncode=1, stdout="", stderr="offline fixture")

        original_run = shared.subprocess.run
        shared.subprocess.run = failed_probe
        try:
            must_fail(lambda: shared.update_dependency_hash(
                ".#codex", "cargoHash", hashes, {"cargoHash": shared.DUMMY_SHA256_HASH}
            ))
        finally:
            shared.subprocess.run = original_run
        assert json.loads(hashes.read_text(encoding="utf-8")) == {"cargoHash": "old"}
        assert not list(root.glob(".hashes.json.*.tmp"))
    PY
    touch "$out"
  ''
