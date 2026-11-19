"""Typed command/wire fixtures. Wrapper process/artifact ownership is separate."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

reader, generated_test = sys.argv[1:]
secret = 'synthetic-token-never-output'
registry = 'Registry.{ { 100 100 500 100 65536 } [ { fixture https://fixture.invalid/ [ { title h1 } ] } ] }'
groups = 0
with tempfile.TemporaryDirectory(prefix='browser-read-tests-') as temporary:
    root = Path(temporary)
    config = root / 'config'
    (config / 'browser-read').mkdir(parents=True)
    filename = config / 'browser-read/registry.datom'
    filename.write_text(registry)
    trace = root / 'trace'
    environment = dict(os.environ,XDG_CONFIG_HOME=str(config),FIXTURE_TRACE=str(trace))

    def invoke(request='Read.{ fixture [ title ] }',mode='success',expected=None,arguments=None):
        global groups
        before = trace.read_text() if trace.exists() else ''
        result = subprocess.run([reader,*(arguments if arguments is not None else [request])],
                                env=dict(environment,FIXTURE_MODE=mode),capture_output=True,text=True,timeout=10)
        assert secret not in result.stdout+result.stderr
        assert 'NEVER-FINAL' not in result.stdout+result.stderr
        assert result.stderr == '',result.stderr
        if expected is not None:
            assert result.stdout.strip() == expected,(mode,result.stdout,expected)
            assert result.returncode == 1
            if any(expected.startswith('Refused.'+phase) for phase in ('InvalidRequest','MissingRegistry','UnreadableRegistry','InvalidRegistry','UnknownPage','UnknownFields')):
                assert (trace.read_text() if trace.exists() else '') == before
        else:
            assert result.returncode == 0,(mode,result.stdout)
            assert result.stdout.startswith('Read.') and 'title' in result.stdout and 'one' in result.stdout
        groups += 1
        return result.stdout

    first = invoke()
    assert first == r'Read.[ { title «one \» two \ three' + '\nline» } ]\n', repr(first)
    for request in ('Read.{ fixture [] }','Read.{ fixture [ title title ] }','Read.{ fixture [ title ]','Read.{ fixture [ title ] } trailing','Read.{ fixture [ «» ] }'):
        invoke(request,expected='Refused.InvalidRequest')
    invoke(arguments=[],expected='Refused.InvalidRequest')
    invoke(arguments=['Read.{ fixture [ title ] }','extra'],expected='Refused.InvalidRequest')
    invoke('Read.{ other [ title ] }',expected='Refused.UnknownPage.other')
    invoke('Read.{ fixture [ absent ] }',expected='Refused.UnknownFields.[ absent ]')
    filename.unlink()
    invoke(expected='Refused.MissingRegistry')
    filename.mkdir()
    invoke(expected='Refused.UnreadableRegistry')
    filename.rmdir()
    filename.write_text('not a registry')
    invoke(expected='Refused.InvalidRegistry')
    for replacement in (registry.replace('100 100 500','0 100 500'),registry.replace('100 100 500','9223372036854775807 100 500'),registry.replace('https://fixture.invalid/','javascript:alert(1)'),registry.replace('https://fixture.invalid/','https://user:password@fixture.invalid/'),registry.replace('{ title h1 }','{ title h1 } { title h2 }')):
        filename.write_text(replacement)
        invoke(expected='Refused.InvalidRegistry')
    filename.write_text(registry)
    for phase in ('SessionAttach','SessionRun','SessionCleanup','ArtifactSetup','ArtifactCleanup','Interrupted'):
        invoke(mode=phase,expected='Refused.'+phase)
    for mode,refusal in (('fields','Fields.[ title ]'),('failed-fields','Fields.[ title ]'),('tab-cleanup','TabCleanup'),('navigation','Navigation'),('tab-open','TabOpen')):
        invoke(mode=mode,expected='Refused.'+refusal)
    for mode in ('unknown-phase','false-error','identity-leak','native-error','bad-json','unknown-fields','duplicate-fields','empty-fields','bad-outcome','extra-value','partial-value','wrong-count','failed-success'):
        invoke(mode=mode,expected='Refused.BrowserOutcome')
    # Registry values are loaded anew and encoded into generated code as data.
    trace.unlink()
    filename.write_text(registry.replace('fixture.invalid','changed.invalid').replace('h1','h2'))
    invoke()
    jobs = list(map(json.loads,trace.read_text().splitlines()))
    assert len(jobs) == 1
    code = jobs[0]['readCode']
    assert 'changed.invalid' in code and 'h2' in code and 'fixture.invalid' not in code
    assert set(jobs[0]) == {'readCode','limits'}
    assert all(isinstance(value,int) and value>0 for value in jobs[0]['limits'].values())
    executed = subprocess.run(['node',generated_test],input=json.dumps(jobs[0]),capture_output=True,text=True,timeout=10)
    assert executed.returncode == 0, executed.stderr
    observed = json.loads(executed.stdout)
    assert observed['urls'] == ['https://changed.invalid/'] and observed['locators'] == ['h2']
    assert observed['result']['values'] == [{'name':'title','value':'synthetic text'}]
    groups += 1
    trace.unlink()
    hostile = 'h1"); globalThis.injected=true; //'
    filename.write_text(registry.replace('h1','«'+hostile+'»'))
    invoke()
    job = json.loads(trace.read_text())
    executed = subprocess.run(['node',generated_test],input=json.dumps(job),capture_output=True,text=True,timeout=10)
    assert executed.returncode == 0, executed.stderr
    assert json.loads(executed.stdout)['locators'] == [hostile]
    groups += 1
print(f'command/wire fixtures: {groups} groups passed')
