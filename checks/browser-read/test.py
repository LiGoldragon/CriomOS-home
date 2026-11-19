"""Adversarial synthetic fixtures; no browser, account, network or GoPass."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

reader, helper, wrapper = sys.argv[1:]
secret = "synthetic-token-never-output"
registry = 'Registry.{ { 100 100 500 100 65536 } [ { fixture https://fixture.invalid/ [ { title h1 } ] } ] }'
groups = 0
with tempfile.TemporaryDirectory(prefix="browser-read-tests-") as temporary:
    root = Path(temporary)
    config = root / "config"
    (config / "browser-read").mkdir(parents=True)
    filename = config / "browser-read/registry.datom"
    filename.write_text(registry)
    trace = root / "trace"
    environment = dict(os.environ, XDG_CONFIG_HOME=str(config), FIXTURE_TRACE=str(trace),
                       PLAYWRIGHT_MCP_EXTENSION_TOKEN=secret)

    def invoke(request='Read.{ fixture [ title ] }', mode='success', expected=None, extra=None, arguments=None):
        global groups
        env = dict(environment, FIXTURE_MODE=mode)
        if extra:
            for key, value in extra.items():
                if value is None:
                    env.pop(key, None)
                else:
                    env[key] = value
        result = subprocess.run([reader, *(arguments if arguments is not None else [request])], env=env, capture_output=True, text=True, timeout=10)
        assert secret not in result.stdout + result.stderr
        assert 'NEVER-FINAL' not in result.stdout + result.stderr
        assert result.stderr == '', result.stderr
        if expected is not None:
            assert result.stdout.strip() == expected, (mode, result.stdout, expected)
            assert result.returncode == 1
        else:
            assert result.returncode == 0, (mode, result.stdout)
            assert result.stdout.startswith('Read.') and 'title' in result.stdout and 'one' in result.stdout
        if trace.exists():
            for entry in map(json.loads, trace.read_text().splitlines()):
                if 'root' in entry:
                    assert not Path(entry['root']).exists(), entry
                if entry.get('event') == 'daemon':
                    try:
                        os.kill(entry['pid'], 0)
                    except ProcessLookupError:
                        pass
                    else:
                        raise AssertionError(('daemon survived result', entry['pid']))
        groups += 1
        return result.stdout

    first = invoke()
    assert '\\»' in first and '\\\\' in first and '\nline' in first
    invoke(extra={
        'PLAYWRIGHT_MCP_INIT_PAGE':'/private-script', 'PLAYWRIGHT_MCP_INIT_SCRIPT':'/private-script',
        'PLAYWRIGHT_MCP_OUTPUT_DIR':str(root/'escape'), 'PWTEST_CLI_GLOBAL_CONFIG':'/private-global',
        'PLAYWRIGHT_CLI_SESSION':'existing-session', 'PLAYWRIGHT_MCP_CDP_ENDPOINT':'http://private.invalid',
        'NODE_OPTIONS':'--require=/private-script', 'NODE_PATH':'/private-path',
    })
    assert not (root/'escape').exists()
    for request in ('Read.{ fixture [] }', 'Read.{ fixture [ title title ] }', 'Read.{ fixture [ title ]', 'Read.{ fixture [ title ] } trailing', 'Read.{ fixture [ «» ] }'):
        invoke(request, expected='Refused.InvalidRequest')
    invoke(arguments=[], expected='Refused.InvalidRequest')
    invoke(arguments=['Read.{ fixture [ title ] }','extra'], expected='Refused.InvalidRequest')
    invoke('Read.{ other [ title ] }', expected='Refused.UnknownPage.other')
    invoke('Read.{ fixture [ absent ] }', expected='Refused.UnknownFields.[ absent ]')
    filename.unlink()
    invoke(expected='Refused.MissingRegistry')
    filename.write_text('not a registry')
    invoke(expected='Refused.InvalidRegistry')
    for replacement in (registry.replace('100 100 500','0 100 500'),registry.replace('https://fixture.invalid/','javascript:alert(1)'),registry.replace('https://fixture.invalid/','https://user:password@fixture.invalid/'),registry.replace('{ title h1 }','{ title h1 } { title h2 }')):
        filename.write_text(replacement)
        invoke(expected='Refused.InvalidRegistry')
    filename.write_text(registry)
    for mode, refusal in (
        ('attach-failure','SessionAttach'),('attach-timeout','SessionAttach'),
        ('run-timeout','TabCleanup'),('fields','Fields.[ title ]'),
        ('tab-cleanup','TabCleanup'),('bad-outcome','BrowserOutcome'),
        ('extra-value','BrowserOutcome'),('output-overflow','TabCleanup'),
        ('daemon-stuck','SessionCleanup'),('ignore-term','SessionCleanup'),
    ):
        invoke(mode=mode, expected='Refused.'+refusal)
    invoke(expected='Refused.SessionAttach',extra={'PLAYWRIGHT_MCP_EXTENSION_TOKEN':''})
    invoke(expected='Refused.SessionAttach',extra={'PLAYWRIGHT_MCP_EXTENSION_TOKEN':None})
    # The registry is read anew, including changed locators and page addresses.
    trace.unlink()
    filename.write_text(registry.replace('fixture.invalid','changed.invalid').replace('h1','h2'))
    invoke()
    recorded = trace.read_text()
    assert 'changed.invalid' in recorded and 'h2' in recorded and 'fixture.invalid' not in recorded

    # Failures after temporary allocation are inside the protected lifetime.
    spec = importlib.util.spec_from_file_location('session', helper)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    task = {'url':'https://fixture.invalid/', 'fields':[{'name':'title','locator':'h1'}],
            'limits':{'navigation_ms':100,'action_ms':100,'command_ms':500,'cleanup_ms':100,'output_bytes':65536}}
    allocated = []
    original_mkdtemp = module.tempfile.mkdtemp
    def allocate(**keywords):
        directory = original_mkdtemp(dir=root, **keywords)
        allocated.append(directory)
        return directory
    with patch.object(module.tempfile,'mkdtemp',allocate), patch.object(module.Path,'write_text',side_effect=OSError('PRIVATE ERROR')):
        assert module.Session(wrapper,task.copy()).run() == module.refused('ArtifactSetup')
    assert allocated and all(not Path(directory).exists() for directory in allocated)
    groups += 1
    outside = root/'outside'
    outside.mkdir()
    (outside/'sentinel').write_text('preserve')
    original_mkdir = module.Path.mkdir
    def mkdir(path, *arguments, **keywords):
        if path.name == 'output':
            path.symlink_to(outside, target_is_directory=True)
        else:
            original_mkdir(path,*arguments,**keywords)
    with patch.object(module.tempfile,'mkdtemp',allocate), patch.object(module.Path,'mkdir',mkdir):
        assert module.Session(wrapper,task.copy()).run() == module.refused('ArtifactSetup')
    assert (outside/'sentinel').read_text() == 'preserve'
    assert all(not Path(directory).exists() for directory in allocated)
    groups += 1
print(f'command/session fixtures: {groups} groups passed')
