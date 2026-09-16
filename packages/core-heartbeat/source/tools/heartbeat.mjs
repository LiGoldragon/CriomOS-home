#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

export const majorKinds = ['main_promoted', 'activation', 'failure', 'living_word_unseen', 'successor_ready', 'none', 'unavailable'];
const hash = text => crypto.createHash('sha256').update(text).digest('hex');
const readTail = (file, limit = 131072) => {
  const fd = fs.openSync(file, 'r');
  try {const size=fs.fstatSync(fd).size, b=Buffer.alloc(Math.min(size,limit));fs.readSync(fd,b,0,b.length,Math.max(0,size-limit));return b.toString('utf8');} finally {fs.closeSync(fd);}
};
const textOf = content => typeof content === 'string' ? content : Array.isArray(content) ? content.filter(x=>['text','input_text'].includes(x.type)).map(x=>x.text??'').join('\n') : null;
export function lastUserTurn(file) {
  try {
    let found=null;
    for(const line of readTail(file,8388608).split('\n')) try {
      const r=JSON.parse(line);let text=null;
      if(r.type==='user') text=textOf(r.message?.content);
      if(r.type==='response_item' && r.payload?.role==='user') text=textOf(r.payload.content);
      if(r.type==='event_msg' && r.payload?.type==='user_message') text=r.payload.message;
      if(typeof text==='string') found={status:'observed',sha256:hash(text),sourceRecord:r.uuid??r.payload?.id??null,at:r.timestamp??null,text:text.slice(-16384),truncated:text.length>16384};
    } catch {}
    return found??{status:'unavailable',reason:'no_complete_user_record_in_tail'};
  } catch {return {status:'unavailable',reason:'transcript_unreadable'};}
}
export function latestQuota(text, now=Date.now()) {
  let latest=null;
  for(const line of text.split('\n')) try {
    const r=JSON.parse(line),at=Date.parse(r.observedAt);
    if(r.kind==='quota' && r.name==='account.primary' && r.windowMinutes===10080 && Number.isFinite(r.remainingPercent) && r.remainingPercent>=0 && r.remainingPercent<=100 && Number.isFinite(at) && at<=now && (!latest || at>Date.parse(latest.observedAt))) latest=r;
  } catch {}
  return latest;
}
export function quotaInterval(quota, now=Date.now(), staleAfterMinutes=120) {
  if(!quota) return {minutes:60,reason:'quota_unknown'};
  const age=now-Date.parse(quota.observedAt),r=quota.remainingPercent;
  if(!Number.isFinite(age)||age<0||age>staleAfterMinutes*60000) return {minutes:60,reason:'quota_stale'};
  return {minutes:r>=50?15:r>=20?30:r>=5?60:120,reason:'quota_observed'};
}
export function collectSnapshot(config,{invoke=spawnSync}={}) {
  const candidates=[],reports=[],lanes=[];
  for(const lane of config.lanes??[]) {
    let r;
    const opts={cwd:lane.repo,encoding:'utf8',timeout:10000,maxBuffer:16384};
    try {
      if(fs.existsSync(path.join(lane.repo,'.jj'))) r=invoke(config.jjBinary??'jj',['--ignore-working-copy','log','--no-graph','-r',lane.bookmark,'-T','commit_id ++ "\\n" ++ description'],opts);
      else {
        r=invoke('git',['log','-1','--format=%H%n%B',lane.bookmark],opts);
        if(r.status!==0) r=invoke('git',['log','-1','--format=%H%n%B','refs/remotes/origin/'+lane.bookmark],opts);
      }
    } catch {r={status:2};}
    const tip=r.status===0?r.stdout.trim():null;
    lanes.push({flow:lane.id,status:tip?'observed':'unavailable'});
    if(tip) candidates.push({id:hash(lane.id+'\n'+tip.split('\n')[0]),kind:'lane_tip',flow:lane.id,text:tip});
    if(lane.transcript) {
      const turn=lastUserTurn(lane.transcript);
      if(turn.status==='observed') candidates.push({id:turn.sha256,kind:'user_turn',flow:lane.id,...turn});
      else lanes.push({flow:lane.id,kind:'user_turn',...turn});
    }
    for(const file of lane.reports??[]) {
      try {reports.push({flow:lane.id,path:file,status:'observed',text:readTail(file,24576)});} catch {reports.push({flow:lane.id,path:file,status:'unavailable'});}
    }
  }
  return {schema:'heartbeat-snapshot/v1',candidates,reports,lanes,recipients:(config.recipients??[]).map(x=>x.id)};
}
export function validateDecision(value,snapshot) {
  if(!value || !majorKinds.includes(value.major) || typeof value.summary!=='string' || value.summary.length>480 || !Array.isArray(value.recipients) || value.recipients.length>8 || value.recipients.some(id=>!snapshot.recipients.includes(id))) throw Error('invalid_decision');
  if(!['none','unavailable'].includes(value.major) && !snapshot.candidates.some(c=>c.id===value.sourceId)) throw Error('unknown_source');
  return {...value,recipients:[...new Set(value.recipients)]};
}
export function deliverOne(recipient,message,config,{invoke=spawnSync}={}) {
  let binary,args;
  if(recipient.route==='codex_queue') {binary=config.codexBinary??'codex';args=['queue','--thread',recipient.session,'--message',message];}
  else if(recipient.route==='prompt_relay') {
    binary=process.execPath;args=[config.promptRelay,'claude','--source',config.messageFile,'--source-format','peer-file','--session-short',recipient.session];
  } else return {recipient:recipient.id,route:'none',receipt_kind:'pending',reason:'unsupported_route'};
  let r;
  try {r=invoke(binary,args,{encoding:'utf8',timeout:20000,maxBuffer:16384});} catch {return {recipient:recipient.id,route:recipient.route,receipt_kind:'pending',reason:'transport_error'};}
  let accepted=false,receipt=null;
  if(r.status===0 && recipient.route==='codex_queue') {const m=(r.stdout??'').match(/Queued message ([0-9a-f-]+)/);accepted=!!m;receipt=m?.[1]??null;}
  if(r.status===0 && recipient.route==='prompt_relay') {try {const v=JSON.parse(r.stdout);accepted=v.kind==='claude-bytes-written-to-pty';receipt=accepted?v.session_id:null;} catch {}}
  return {recipient:recipient.id,route:recipient.route,receipt_kind:accepted?'accepted':'pending',receipt,reason:accepted?null:'transport_refused_or_unrecognized'};
}
export function witness(recipient,identity) {
  if(!recipient.transcript) return false;
  try {
    for(const line of readTail(recipient.transcript,262144).split('\n')) try {
      const r=JSON.parse(line);
      const text=r.type==='user'?textOf(r.message?.content):r.type==='response_item'&&r.payload?.role==='user'?textOf(r.payload.content):null;
      if(text?.includes('"identity":"'+identity+'"')) return {record:r.uuid??r.payload?.id??null,at:r.timestamp??null};
    } catch {}
  } catch {}
  return false;
}
const atomic = (file,value) => {fs.mkdirSync(path.dirname(file),{recursive:true});const tmp=file+'.'+process.pid+'.tmp';fs.writeFileSync(tmp,JSON.stringify(value)+'\n',{mode:0o600});fs.renameSync(tmp,file);};
export async function heartbeat({config,now=()=>new Date().toISOString(),luna,invoke=spawnSync,collect=collectSnapshot}) {
  const at=now(),nowMs=Date.parse(at);let quota=null;
  try {quota=latestQuota(readTail(config.quotaEventLog),nowMs);} catch {}
  const interval=quotaInterval(quota,nowMs,config.staleAfterMinutes??120);
  let state={events:{}};
  if(fs.existsSync(config.stateFile)) state=JSON.parse(fs.readFileSync(config.stateFile,'utf8'));
  fs.mkdirSync(path.dirname(config.reportFile),{recursive:true});
  const emit=e=>{fs.appendFileSync(config.reportFile,JSON.stringify(e)+'\n',{mode:0o600});return e;};
  if(state.lastRun && nowMs<Date.parse(state.lastRun)+interval.minutes*60000) return emit({schema:'heartbeat/v1',at,kind:'suppressed',interval,reason:'cadence'});
  const snapshot=collect(config,{invoke});snapshot.receipts=state.events;
  let decision;
  try {decision=validateDecision(await luna(snapshot),snapshot);} catch {decision={major:'unavailable',sourceId:null,summary:'Classifier unavailable or invalid output',recipients:[]};}
  const event={schema:'heartbeat/v1',at,kind:'heartbeat',interval,quota:quota?{remainingPercent:quota.remainingPercent,observedAt:quota.observedAt}:null,decision,deliveries:[],file_report:{receipt_kind:'file_only'}};
  const major=!['none','unavailable'].includes(decision.major);
  const identity=major?hash(decision.major+'\n'+decision.sourceId):null;event.identity=identity;
  if(major) {
    const prior=state.events[identity]??{},receipts={...prior};
    const message=JSON.stringify({type:'Heartbeat',identity,major:decision.major,sourceId:decision.sourceId,summary:decision.summary,previousReceipts:prior,intendedRecipients:decision.recipients,receiptReport:config.reportFile});
    atomic(config.messageFile,JSON.parse(message));
    for(const id of decision.recipients) {
      const recipient=config.recipients.find(r=>r.id===id);
      let result=prior[id];
      if(!result || result.receipt_kind==='pending') {
        result=config.send===true?deliverOne(recipient,message,config,{invoke}):{recipient:id,route:recipient.route,receipt_kind:'pending',reason:'send_disabled'};
      }
      const observed=witness(recipient,identity);
      if(observed) result={...result,receipt_kind:'transcript_witnessed',witness:observed};
      receipts[id]=result;event.deliveries.push(result);
      // Persist each acceptance before attempting another recipient. A crash in
      // the send/commit gap is still ambiguous; no exactly-once claim is made.
      state.events[identity]=receipts;atomic(config.stateFile,state);
    }
  }
  state.lastRun=at;atomic(config.stateFile,state);return emit(event);
}
async function main() {
  const file=process.argv[2];if(!file) throw Error('usage: heartbeat CONFIG');
  const config=JSON.parse(fs.readFileSync(file,'utf8'));
  fs.mkdirSync(path.dirname(config.stateFile),{recursive:true});
  if(process.env.HEARTBEAT_LOCK_HELD!=='1') {
    const r=spawnSync('flock',['--nonblock','--conflict-exit-code','75',config.stateFile+'.lock',process.execPath,process.argv[1],file],{stdio:'inherit',env:{...process.env,HEARTBEAT_LOCK_HELD:'1'}});
    process.exitCode=r.status??2;return;
  }
  const luna=config.luna===true?(await import('./heartbeat-luna.mjs')).runLunaWakeCheck:async()=>({major:'unavailable',sourceId:null,summary:'Luna disabled',recipients:[]});
  const result=await heartbeat({config,luna:snapshot=>luna(snapshot,config.lunaOptions??{})});process.stdout.write(JSON.stringify(result)+'\n');
}
if(process.argv[1]===new URL(import.meta.url).pathname) main().catch(e=>{process.stderr.write(e.message+'\n');process.exitCode=2;});
