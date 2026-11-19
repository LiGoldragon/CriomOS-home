'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(process.argv[2], 'utf8');
// Match upstream's fresh VM: standard JavaScript and the supplied Page only.
const execute = vm.runInNewContext('(page, task) => { const module = {exports:{}}; ' + source + '; return module.exports.readPage(page,task); }');
const readPage = async (page, task) => JSON.parse(JSON.stringify(await execute(page,task)));

async function scenario(mode, fields = [{name:'title', locator:'h1'}]) {
  const calls = [];
  let closed = false;
  const tab = {
    setDefaultTimeout: ms => calls.push(['timeout',ms]),
    goto: async (url, options) => { calls.push(['goto',url,options]); if (mode === 'navigation') throw Error('PRIVATE PAGE DUMP'); },
    locator: locator => ({
      count: async () => mode === 'count-hang' ? new Promise(()=>{}) : mode === 'multiple' ? 2 : mode === 'absent' ? 0 : 1,
      innerText: async options => { calls.push(['text',locator,options]); if (mode === 'locator') throw Error('PRIVATE PAGE DUMP'); return locator === 'h1' ? 'one » two \\ three\nline' : 'secondary'; }
    }),
    close: async options => { calls.push(['close',options]); if (mode === 'close') throw Error('PRIVATE PAGE DUMP'); if (mode === 'close-hang') return new Promise(()=>{}); closed = true; },
    isClosed: () => { calls.push(['isClosed']); return mode === 'unconfirmed' ? false : closed; }
  };
  const context = {
    newPage: async () => { calls.push(['newPage']); if (mode === 'open') throw Error('PRIVATE PAGE DUMP'); if (mode === 'open-hang') return new Promise(()=>{}); return tab; },
    browser: () => ({isConnected: () => mode !== 'disconnected'})
  };
  const page = {context: () => context, waitForTimeout: ms => new Promise(resolve => setTimeout(resolve,ms))};
  const task = {marker:'synthetic', url:'https://fixture.invalid/', fields, limits:{action_ms:100, navigation_ms:100, cleanup_ms:100}};
  const result = await readPage(page, task);
  assert(!JSON.stringify(result).includes('PRIVATE PAGE DUMP'));
  if (!['open','open-hang'].includes(mode)) assert(calls.some(c => c[0] === 'close'));
  if (!['close','open','close-hang','open-hang'].includes(mode)) assert(calls.some(c => c[0] === 'isClosed'));
  return {result, calls, page, task};
}
(async () => {
  assert.deepEqual((await scenario('success')).result, {phase:'Read',values:[{name:'title',value:'one » two \\ three\nline'}]});
  assert.deepEqual((await scenario('success', [{name:'second',locator:'.second'},{name:'title',locator:'h1'}])).result.values.map(v=>v.name), ['second','title']);
  for (const mode of ['multiple','absent','locator','count-hang']) assert.deepEqual((await scenario(mode)).result,{phase:'Refused',refusal:{Fields:['title']}});
  assert.deepEqual((await scenario('navigation')).result,{phase:'Refused',refusal:'Navigation'});
  for (const mode of ['close','unconfirmed','disconnected','open','close-hang','open-hang']) assert.deepEqual((await scenario(mode)).result,{phase:'Refused',refusal:'TabCleanup'});
  console.log('page fixtures: 13 groups passed');
})().catch(error => {console.error(error); process.exitCode=1;});
