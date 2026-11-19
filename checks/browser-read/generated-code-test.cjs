'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const job = JSON.parse(fs.readFileSync(0,'utf8'));
const observed = {urls:[],locators:[]};
let closed = false;
const tab = {
  setDefaultTimeout() {},
  goto: async url => observed.urls.push(url),
  locator: locator => ({count:async()=>1,innerText:async()=>{observed.locators.push(locator);return 'synthetic text';}}),
  close: async () => {closed=true;},
  isClosed: () => closed,
};
const page = {
  context: () => ({newPage:async()=>tab,browser:()=>({isConnected:()=>true})}),
  waitForTimeout: ms => new Promise(resolve=>setTimeout(resolve,ms)),
};
(async()=>{
  const sandbox = {};
  const read = vm.runInNewContext('('+job.readCode+')',sandbox);
  const result = JSON.parse(JSON.stringify(await read(page)));
  assert.equal(sandbox.injected,undefined);
  assert.equal(closed,true);
  assert.equal(result.phase,'Read');
  assert.equal(result.values.length,observed.locators.length);
  process.stdout.write(JSON.stringify({result,...observed}));
})().catch(error=>{console.error(error);process.exitCode=1;});
