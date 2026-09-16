import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {heartbeat,latestQuota,quotaInterval,lastUserTurn,validateDecision,deliverOne} from './heartbeat.mjs';
const fixture=name=>fs.readFileSync(new URL('./fixtures/heartbeat/'+name,import.meta.url),'utf8');
const snapshot=()=>JSON.parse(fixture('snapshot.json'));
const decision=()=>JSON.parse(fixture('decision.json'));
const temp=t=>{const dir=fs.mkdtempSync(path.join(os.tmpdir(),'heartbeat-test-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));return dir;};
const configure=dir=>{const q=path.join(dir,'quota');fs.writeFileSync(q,fixture('quota.ndjson'));return {quotaEventLog:q,stateFile:path.join(dir,'state'),reportFile:path.join(dir,'report.ndjson'),messageFile:path.join(dir,'message.json'),recipients:[{id:'efa157',route:'prompt_relay',session:'claude-id'},{id:'d9961c',route:'codex_queue',session:'codex-id'}],send:true,promptRelay:'/fixture/relay'};};
test('uses only valid weekly primary quota despite newer other-window and invalid rows',()=>{
 const q=latestQuota(fixture('quota.ndjson'),Date.parse('2026-09-16T16:00:00Z'));assert.equal(q.remainingPercent,16);
 assert.deepEqual(quotaInterval(q,Date.parse('2026-09-16T16:00:00Z')),{minutes:60,reason:'quota_observed'});
 assert.equal(quotaInterval(q,Date.parse('2026-09-16T20:00:00Z')).reason,'quota_stale');
 for(const [remainingPercent,minutes] of [[90,15],[30,30],[10,60],[1,120]]) assert.equal(quotaInterval({...q,remainingPercent},Date.parse('2026-09-16T16:00:00Z')).minutes,minutes);
});
test('reads actual Codex and Claude user record shapes and ignores assistant text',()=>{
 const c=lastUserTurn(new URL('./fixtures/heartbeat/codex.jsonl',import.meta.url));
 const a=lastUserTurn(new URL('./fixtures/heartbeat/claude.jsonl',import.meta.url));
 assert.equal(c.text,'Please publish the ready successor package.');assert.equal(c.sha256,a.sha256);
 assert.equal(lastUserTurn('/nonexistent-transcript').status,'unavailable');
});
test('rejects invented sources and unknown recipients before a send',()=>{
 assert.throws(()=>validateDecision({...decision(),sourceId:'fabricated'},snapshot()));
 assert.throws(()=>validateDecision({...decision(),recipients:['unregistered']},snapshot()));
});
test('cadence skips Luna; later retry only targets pending recipients',async t=>{
 const cfg=configure(temp(t));let calls=0;const sends=[];
 const invoke=(bin,args)=>{sends.push(args);return bin===process.execPath?{status:2,stdout:'refused'}:{status:0,stdout:'Queued message 1111-2222 for thread codex-id'};};
 const run=at=>heartbeat({config:cfg,now:()=>at,collect:snapshot,luna:async()=>{calls++;return decision();},invoke});
 const first=await run('2026-09-16T16:00:00Z');assert.deepEqual(first.deliveries.map(r=>r.receipt_kind),['pending','accepted']);
 const skipped=await run('2026-09-16T16:05:00Z');assert.equal(skipped.kind,'suppressed');assert.equal(calls,1);
 await run('2026-09-16T17:00:00Z');assert.equal(calls,2);assert.equal(sends.length,3);assert.equal(sends[2][1],'claude');
});
test('quiet and invalid decisions have no transport effects',async t=>{
 const cfg=configure(temp(t));let sends=0;
 const r=await heartbeat({config:cfg,now:()=> '2026-09-16T16:00:00Z',collect:snapshot,luna:async()=>({...decision(),major:'shell'}),invoke:()=>{sends++;return {status:0};}});
 assert.equal(sends,0);assert.equal(r.decision.major,'unavailable');
});
test('queue adapter sends payload to a real child fixture, not an argv echo',t=>{
 const dir=temp(t),wrapper=path.join(dir,'queue'),capture=path.join(dir,'capture');
 const fake=new URL('./fixtures/heartbeat/fake-queue.mjs',import.meta.url).pathname;
 fs.writeFileSync(wrapper,'#!'+process.execPath+'\nimport('+JSON.stringify('file://'+fake)+');\n',{mode:0o700});
 const old=process.env.HEARTBEAT_TEST_CAPTURE;process.env.HEARTBEAT_TEST_CAPTURE=capture;t.after(()=>{if(old===undefined)delete process.env.HEARTBEAT_TEST_CAPTURE;else process.env.HEARTBEAT_TEST_CAPTURE=old;});
 const message=JSON.stringify({type:'Heartbeat',identity:'event-one'});
 const r=deliverOne({id:'d9961c',route:'codex_queue',session:'thread-one'},message,{codexBinary:wrapper});
 assert.equal(r.receipt_kind,'accepted');assert.equal(fs.readFileSync(capture,'utf8'),message);
});
test('CLI runs with no model and records unavailable rather than fake readiness',t=>{
 const dir=temp(t),cfg=configure(dir);cfg.send=false;cfg.lanes=[];
 const p=path.join(dir,'config');fs.writeFileSync(p,JSON.stringify(cfg));
 const r=spawnSync(process.execPath,[new URL('./heartbeat.mjs',import.meta.url).pathname,p],{encoding:'utf8'});
 assert.equal(r.status,0,r.stderr);assert.equal(JSON.parse(r.stdout).decision.major,'unavailable');
});

test('Luna adapter refuses a rejected boundary without starting a model turn',async()=>{
 const {runLunaWakeCheck}=await import('./heartbeat-luna.mjs');let turnStarted=false;
 const transport={notify:async()=>{},request:async(method,params)=>{
  if(method==='initialize')return {};
  if(method==='model/list')return {data:[{model:'gpt-5.6-luna'}]};
  if(method==='thread/start'){assert.deepEqual(params.environments,[]);assert.equal(params.config['features.shell_tool'],false);assert.equal(params.config['mcp_servers.fixture.enabled'],false);throw Error('boundary refused');}
  if(method==='turn/start'){turnStarted=true;}return {};
 }};
 const r=await runLunaWakeCheck(snapshot(),{transport,invoke:()=>({status:0,stdout:'{"names":["fixture"]}'})});
 assert.equal(r.major,'unavailable');assert.equal(r.witness.boundaryAccepted,false);assert.equal(turnStarted,false);
});
