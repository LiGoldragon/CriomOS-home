#!/usr/bin/env python3
"""Offline release/atomic-update fixtures; never contact a server or auth home."""
import base64
import contextlib
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('codex_update', Path(__file__).with_name('update.py'))
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def fixture(version='1.2.3'):
    assets, contents = [], {}
    for target in updater.TARGETS.values():
        for prefix in ('codex', 'codex-code-mode-host'):
            name = f'{prefix}-{target}.tar.gz'
            url = f'https://github.com/openai/codex/releases/download/rust-v{version}/{name}'
            content = f'{version}/{name}'.encode()
            contents[url] = content
            assets.append({'name': name, 'browser_download_url': url,
                           'digest': 'sha256:' + hashlib.sha256(content).hexdigest()})
    return {'tag_name': 'rust-v' + version, 'draft': False, 'prerelease': False, 'assets': assets}, contents


def manifest(version='1.2.3'):
    release, contents = fixture(version)
    with patch.object(updater, 'fetch_bytes', side_effect=contents.__getitem__):
        return updater.release_manifest(release)


class ReleaseTests(unittest.TestCase):
    def test_all_cli_and_companion_bytes_match_published_digests(self):
        release, contents = fixture()
        with patch.object(updater, 'fetch_bytes', side_effect=contents.__getitem__) as fetch:
            result = updater.release_manifest(release)
        self.assertEqual(fetch.call_count, 4)
        self.assertEqual(result['version'], '1.2.3')
        for row in result['targets'].values():
            for key in ('cli', 'codeModeHost'):
                self.assertEqual(row[key]['hash'], 'sha256-' + base64.b64encode(hashlib.sha256(contents[row[key]['url']]).digest()).decode())

    def test_missing_companion_refuses_before_any_download(self):
        release, _ = fixture()
        release['assets'].pop()
        with patch.object(updater, 'fetch_bytes') as fetch:
            with self.assertRaisesRegex(ValueError, 'Missing required'):
                updater.release_manifest(release)
            fetch.assert_not_called()

    def test_changed_content_refuses(self):
        release, _ = fixture()
        with patch.object(updater, 'fetch_bytes', return_value=b'corrupt'):
            with self.assertRaisesRegex(ValueError, 'digest mismatch'):
                updater.release_manifest(release)

    def test_prerelease_draft_and_nonstable_tags_refuse(self):
        for change in ({'prerelease': True}, {'draft': True}, {'tag_name': 'rust-v1.2.3-alpha.1'}):
            release, _ = fixture()
            release.update(change)
            with self.assertRaisesRegex(ValueError, 'published stable'):
                updater.release_manifest(release)

    def test_unknown_strategy_target_and_redirected_url_refuse(self):
        original = manifest()
        for change in ('strategy', 'target', 'url'):
            data = copy.deepcopy(original)
            if change == 'strategy': data['strategy'] = 'source'
            if change == 'target': data['targets']['new-system'] = {}
            if change == 'url': data['targets']['x86_64-linux']['cli']['url'] = 'https://example.invalid/tool'
            with self.assertRaises(ValueError): updater.validate_manifest(data)

    def invoke(self, current, args, release=None, contents=None):
        root = Path(self.directory.name)
        (root / 'flake.nix').write_text('{}')
        path = root / 'owned-agents/codex/hashes.json'
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(current))
        before = path.read_bytes()
        with patch.object(sys, 'argv', ['update.py', '--root', str(root), *args]), patch.object(updater, 'fetch_json', return_value=release) as fetch, patch.object(updater, 'fetch_bytes', side_effect=(contents or {}).__getitem__), contextlib.redirect_stdout(io.StringIO()) as output:
            updater.main()
        return path, before, fetch, output.getvalue()

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

    def test_show_current_is_offline_and_reads_consumed_manifest(self):
        path, before, fetch, output = self.invoke(manifest(), ['--show-current'])
        self.assertEqual(output.strip(), '1.2.3')
        self.assertEqual(path.read_bytes(), before)
        fetch.assert_not_called()

    def test_exact_version_updates_complete_manifest_without_nix(self):
        release, contents = fixture('1.2.4')
        path, _, fetch, _ = self.invoke(manifest(), ['--version', '1.2.4'], release, contents)
        self.assertEqual(json.loads(path.read_text()), manifest('1.2.4'))
        fetch.assert_called_once_with(updater.RELEASES + '/tags/rust-v1.2.4')

    def test_same_version_changed_identity_preserves_original_file(self):
        current = manifest()
        current['targets']['x86_64-linux']['cli']['hash'] = 'sha256-' + base64.b64encode(b'x' * 32).decode()
        release, contents = fixture()
        with self.assertRaisesRegex(ValueError, 'Immutable release'):
            self.invoke(current, [], release, contents)
        path = Path(self.directory.name) / 'owned-agents/codex/hashes.json'
        self.assertEqual(json.loads(path.read_text()), current)

    def test_metadata_for_another_version_does_not_override_exact_request(self):
        current = manifest()
        release, contents = fixture('1.2.5')
        with self.assertRaisesRegex(ValueError, 'requested version'):
            self.invoke(current, ['--version', '1.2.4'], release, contents)
        path = Path(self.directory.name) / 'owned-agents/codex/hashes.json'
        self.assertEqual(json.loads(path.read_text()), current)

    def test_failed_companion_download_preserves_original_file(self):
        current = manifest()
        release, contents = fixture('1.2.4')
        contents.pop(next(iter(contents)))
        with self.assertRaises(KeyError): self.invoke(current, [], release, contents)
        path = Path(self.directory.name) / 'owned-agents/codex/hashes.json'
        self.assertEqual(json.loads(path.read_text()), current)


if __name__ == '__main__':
    unittest.main()
