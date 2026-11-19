'use strict';
const assert = require('node:assert/strict');
const {readPage} = require(process.argv[2]);

async function scenario(mode, fields = [{name:'title', locator:'h1'}]) {
  const calls = [];
  let closed = false;
  const tab = {
    setDefaultTimeout: ms => calls.push(['timeout',ms]),
    goto: async (url, options) => { calls.push(['goto',url,options]); if (mode === 'navigation') throw Error('PRIVATE PAGE DUMP'); },
    locator: locator => ({
      count: async () => mode === 'multiple' ? 2 : mode === 'absent' ? 0 : 1,
      innerText: async options => { calls.push(['text',locator,options]); if (mode === 'locator') throw Error('PRIVATE PAGE DUMP'); return locator === 'h1' ? 'one » two \\ three\nline' : 'secondary'; }
    }),
    close: async options => { calls.push(['close',options]); if (mode === 'close') throw Error('PRIVATE PAGE DUMP'); closed = true; },
    isClosed: () => { calls.push(['isClosed']); return mode === 'unconfirmed' ? false : closed; }
  };
  const context = {
    newPage: async () => { calls.push(['newPage']); if (mode === 'open') throw Error('PRIVATE PAGE DUMP'); return tab; },
    browser: () => ({isConnected: () => mode !== 'disconnected'})
  };
  const page = {context: () => context};
  const task = {marker:'synthetic', url:'https://fixture.invalid/', fields, limits:{action_ms:100, navigation_ms:100, cleanup_ms:100}};
  const result = await readPage(page, task);
  assert(!JSON.stringify(result).includes('PRIVATE PAGE DUMP'));
  if (mode !== 'open') assert(calls.some(c => c[0] === 'close'));
  if (!['close','open'].includes(mode)) assert(calls.some(c => c[0] === 'isClosed'));
  return {result, calls, page, task};
}
(async () => {
  assert.deepEqual((await scenario('success')).result, {phase:'Read',values:[{name:'title',value:'one » two \\ three\nline'}]});
  assert.deepEqual((await scenario('success', [{name:'second',locator:'.second'},{name:'title',locator:'h1'}])).result.values.map(v=>v.name), ['second','title']);
  for (const mode of ['multiple','absent','locator']) assert.deepEqual((await scenario(mode)).result,{phase:'Refused',refusal:{Fields:['title']}});
  assert.deepEqual((await scenario('navigation')).result,{phase:'Refused',refusal:'Navigation'});
  for (const mode of ['close','unconfirmed','disconnected','open']) assert.deepEqual((await scenario(mode)).result,{phase:'Refused',refusal:'TabCleanup'});
  console.log('page fixtures: 10 groups passed');
})().catch(error => {console.error(error); process.exitCode=1;});
