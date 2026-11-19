"""Synthetic manager/CLI fixtures. No user bus, browser, or credential access."""
import importlib.util
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SOURCE = Path(sys.argv.pop()).resolve()
spec = importlib.util.spec_from_file_location("owned_session", SOURCE)
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)

MANAGER = r'''#!/usr/bin/env python3
import ctypes, json, os, pathlib, signal, subprocess, sys, threading
ctypes.CDLL(None).prctl(36,1,0,0,0)
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
unit=next(x.split('=',1)[1] for x in sys.argv if x.startswith('--unit='))
(root/'manager').write_text(str(os.getpid()))
(root/'arguments').write_text(json.dumps(sys.argv))
(root/'events').write_text('populated 1\n')
os.environ['FIXTURE_UNIT']=unit
args=sys.argv[sys.argv.index('--')+1:]
bootstrap="import os,pathlib,runpy,sys; original=pathlib.Path.read_text; pathlib.Path.read_text=lambda p,*a,**k: ('0::/'+os.environ['FIXTURE_UNIT']+'\\n') if str(p)=='/proc/self/cgroup' else original(p,*a,**k); sys.argv=sys.argv[1:]; runpy.run_path(sys.argv[0],run_name='__main__')"
child=subprocess.Popen([args[0],'-c',bootstrap,*args[1:]])
stopped=threading.Event()
def stop(*unused):
    stopped.set()
    try: child.kill()
    except ProcessLookupError: pass
signal.signal(signal.SIGTERM,stop)
code=child.wait()
stopped.wait()
# Only fixture-owned PIDs are recorded, including a setsid daemon. This is a
# synthetic model of the scope's membership, not a cgroup implementation.
if (root/'pids').exists():
    for text in (root/'pids').read_text().split():
        try: os.kill(int(text),signal.SIGKILL)
        except ProcessLookupError: pass
while True:
    try: os.waitpid(-1,0)
    except ChildProcessError: break
(root/'events').write_text('populated 0\n')
sys.exit(0 if code==0 else 1)
'''
CONTROL = r'''#!/usr/bin/env python3
import os,pathlib,signal
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
(root/'stop').write_text('stop')
try: os.kill(int((root/'manager').read_text()),signal.SIGTERM)
except ProcessLookupError: pass
'''
CLI = r'''#!/usr/bin/env python3
import json,os,pathlib,subprocess,sys,time
root=pathlib.Path(os.environ['FIXTURE_ROOT'])
mode=os.environ['FIXTURE_MODE']
with (root/'pids').open('a') as out: out.write(str(os.getpid())+'\n')
if 'attach' in sys.argv:
    child=subprocess.Popen([sys.executable,'-c',"import os,pathlib,signal; p=pathlib.Path(os.environ['FIXTURE_ROOT'])/'pids'; f=p.open('a'); f.write(str(os.getpid())+'\\n'); f.close(); signal.pause()"],start_new_session=True,stdin=subprocess.DEVNULL,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    # Log the exact child before attach can time out; no identity is returned.
    with (root/'pids').open('a') as out: out.write(str(child.pid)+'\n')
    if mode=='attach-timeout':
        import signal; signal.pause()
    if mode=='attach-failed':
        print('secret-native-error',file=sys.stderr); sys.exit(1)
    print(json.dumps({'pid':child.pid,'session':'fixture','snapshot':'private-page-dump'}))
elif 'run-code' in sys.argv:
    assert not any(k in os.environ for k in ('PLAYWRIGHT_MCP_INIT_SCRIPT','PLAYWRIGHT_MCP_OUTPUT_DIR','NODE_OPTIONS'))
    assert pathlib.Path(os.environ['TMPDIR']).parent.name.startswith('browser-read-')
    if mode=='run-failed':sys.exit(1)
    if mode=='run-timeout':
        import signal; signal.pause()
    if mode=='overflow':print('x'*10000)
    else:print(json.dumps({'result':'{"requested":"value"}'}))
elif 'detach' in sys.argv:
    if mode=='detach-failed':sys.exit(1)
    print('{}')
'''


class OwnedScopeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        for name, body in (("runner", MANAGER), ("control", CONTROL), ("cli", CLI)):
            path = self.root / name
            path.write_text(body)
            path.chmod(0o700)
        self.unrelated = subprocess.Popen([sys.executable, "-c", "import signal; signal.pause()"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.environment = mock.patch.dict(os.environ, {"FIXTURE_ROOT": str(self.root),
            "FIXTURE_MODE": "success", "PLAYWRIGHT_MCP_INIT_SCRIPT": "forbidden",
            "PLAYWRIGHT_MCP_OUTPUT_DIR": "/escape", "NODE_OPTIONS": "forbidden",
            "PLAYWRIGHT_MCP_EXTENSION_TOKEN": "fixture-private-token"})
        self.environment.start()
        self.original_open = os.open
        def opened(path, *args, **kwargs):
            if str(path).startswith('/sys/fs/cgroup/'):
                path = self.root / 'events'
            return self.original_open(path, *args, **kwargs)
        self.open_patch = mock.patch.object(session.os, 'open', opened)
        self.open_patch.start()
        self.scratch = mock.patch.object(session.tempfile, 'tempdir', str(self.root))
        self.scratch.start()

    def tearDown(self):
        self.scratch.stop()
        self.open_patch.stop()
        self.environment.stop()
        self.unrelated.kill()
        self.unrelated.wait()
        self.temporary.cleanup()

    def run_session(self, mode='success'):
        os.environ['FIXTURE_MODE'] = mode
        request = {'readCode':'async page => "fixture"', 'limits':{
            'navigation_ms':1000,'action_ms':1000,'command_ms':500,
            'cleanup_ms':3000,'output_bytes':2048}}
        result = session.supervise(str(self.root/'cli'), str(self.root/'runner'), str(self.root/'control'), request)
        self.assertEqual([], list(self.root.glob('browser-read-*')))
        if (self.root/'pids').exists():
            for text in (self.root/'pids').read_text().split():
                with self.assertRaises(ProcessLookupError):os.kill(int(text),0)
        os.kill(self.unrelated.pid, 0)
        encoded = json.dumps(result)
        self.assertNotIn('fixture-private-token',encoded)
        self.assertNotIn('private-page-dump',encoded)
        self.assertNotIn('secret-native-error',encoded)
        args=json.loads((self.root/'arguments').read_text())
        self.assertIn('--scope',args)
        self.assertIn('--property=KillMode=control-group',args)
        self.assertIn('--property=SendSIGKILL=yes',args)
        self.assertNotIn('fixture-private-token',json.dumps(args))
        self.assertTrue((self.root/'stop').exists())
        return result

    def test_success_waits_for_detached_daemon_and_private_artifacts(self):
        self.assertEqual({'result':'{"requested":"value"}'},self.run_session())

    def test_attach_failure_stops_detached_daemon_before_refusal(self):
        self.assertEqual(session.refusal('SessionAttach'),self.run_session('attach-failed'))

    def test_attach_timeout_stops_detached_daemon_before_refusal(self):
        self.assertEqual(session.refusal('SessionAttach'),self.run_session('attach-timeout'))

    def test_run_failure(self):
        self.assertEqual(session.refusal('SessionRun'),self.run_session('run-failed'))

    def test_run_timeout_is_reported_in_its_own_phase(self):
        self.assertEqual(session.refusal('SessionRun'),self.run_session('run-timeout'))

    def test_output_bound(self):
        self.assertEqual(session.refusal('SessionRun'),self.run_session('overflow'))

    def test_detach_failure_still_stops_scope(self):
        self.assertEqual(session.refusal('SessionCleanup'),self.run_session('detach-failed'))

    def test_interrupted_before_execution_grant_stops_scope(self):
        with mock.patch.object(session, 'send', side_effect=session.Failure('Interrupted')):
            self.assertEqual(session.refusal('Interrupted'), self.run_session())
        self.assertFalse((self.root/'pids').exists())

    def test_manager_failure_before_scope_starts_no_command(self):
        (self.root/'runner').write_text('#!/usr/bin/env python3\nraise SystemExit(1)\n')
        request = {'readCode':'code','limits':{'navigation_ms':1,'action_ms':1,
            'command_ms':500,'cleanup_ms':1000,'output_bytes':2048}}
        result = session.supervise('unused',str(self.root/'runner'),'unused',request)
        self.assertEqual(session.refusal('SessionAttach'),result)
        self.assertEqual([],list(self.root.glob('browser-read-*')))
        self.assertFalse((self.root/'pids').exists())

    def test_manager_timeout_before_scope_grant_starts_no_command(self):
        (self.root/'runner').write_text('#!/usr/bin/env python3\nimport signal; signal.pause()\n')
        request = {'readCode':'code','limits':{'navigation_ms':1,'action_ms':1,
            'command_ms':100,'cleanup_ms':1000,'output_bytes':2048}}
        result = session.supervise('unused',str(self.root/'runner'),'unused',request)
        self.assertEqual(session.refusal('SessionAttach'),result)
        self.assertEqual([],list(self.root.glob('browser-read-*')))
        self.assertFalse((self.root/'pids').exists())

    def test_invalid_limits_start_no_process(self):
        with self.assertRaises(session.Failure):
            session.supervise('unused','unused','unused',{'readCode':'code','limits':{}})
        self.assertFalse((self.root/'manager').exists())


if __name__ == '__main__':
    unittest.main()
