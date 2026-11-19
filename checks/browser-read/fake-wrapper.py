#!/usr/bin/env python3
"""Synthetic read-session boundary. No browser, daemon, GoPass or cleanup."""
import json
import os
from pathlib import Path
import sys

assert sys.argv[1:] == ['read-session']
job = json.load(sys.stdin)
assert set(job) == {'readCode', 'limits'}
assert set(job['limits']) == {'navigation_ms','action_ms','command_ms','cleanup_ms','output_bytes'}
assert isinstance(job['readCode'],str)
with Path(os.environ['FIXTURE_TRACE']).open('a') as trace:
    trace.write(json.dumps(job)+'\n')
mode = os.environ.get('FIXTURE_MODE','success')
if mode in ('SessionAttach','SessionRun','SessionCleanup','ArtifactSetup','ArtifactCleanup','Interrupted'):
    print(json.dumps({'isError':True,'phase':mode}))
    raise SystemExit(1)
if mode == 'unknown-phase':
    print(json.dumps({'isError':True,'phase':'UnknownPage'}))
elif mode == 'false-error':
    print(json.dumps({'isError':False,'phase':'SessionRun'}))
elif mode == 'identity-leak':
    print(json.dumps({'result':'{}','pid':123}))
elif mode == 'native-error':
    print('NEVER-FINAL synthetic-token-never-output',file=sys.stderr)
    print(json.dumps({'isError':True,'error':'NEVER-FINAL synthetic-token-never-output'}))
elif mode == 'bad-json':
    print('NEVER-FINAL synthetic-token-never-output')
else:
    if mode in ('fields','failed-fields'):
        observation = {'phase':'Refused','refusal':{'Fields':['title']}}
    elif mode == 'unknown-fields':
        observation = {'phase':'Refused','refusal':{'Fields':['absent']}}
    elif mode == 'duplicate-fields':
        observation = {'phase':'Refused','refusal':{'Fields':['title','title']}}
    elif mode == 'empty-fields':
        observation = {'phase':'Refused','refusal':{'Fields':[]}}
    elif mode == 'tab-cleanup':
        observation = {'phase':'Refused','refusal':'TabCleanup'}
    elif mode == 'navigation':
        observation = {'phase':'Refused','refusal':'Navigation'}
    elif mode == 'tab-open':
        observation = {'phase':'Refused','refusal':'TabOpen'}
    elif mode == 'bad-outcome':
        observation = {'phase':'Read','values':[{'name':'other','value':'NEVER-FINAL'}]}
    elif mode == 'extra-value':
        observation = {'phase':'Read','values':[{'name':'title','value':'ok','dump':'NEVER-FINAL'}]}
    elif mode == 'partial-value':
        observation = {'phase':'Refused','refusal':'TabCleanup','values':[{'name':'title','value':'NEVER-FINAL'}]}
    elif mode == 'wrong-count':
        observation = {'phase':'Read','values':[]}
    else:
        observation = {'phase':'Read','values':[{'name':'title','value':'one » two \\ three\nline'}]}
    print(json.dumps({'result':json.dumps(observation)}))
    if mode in ('failed-success','failed-fields'):
        raise SystemExit(1)
