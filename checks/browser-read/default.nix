{ pkgs, ... }:
let
  browserRead = import ../../packages/playwright-cli/browser-read.nix { inherit pkgs; };
  tests = pkgs.writeText "browser-read-test.cjs" ''
    'use strict';
    const assert = require('node:assert/strict');
    const fs = require('node:fs');
    const childProcess = require('node:child_process');
    const reader = require(process.argv[2]);
    const configured = 'Registry.{ { 1001 1002 1003 100000 } [ { billing https://fixture.invalid/billing [ { balance «#balance» } ] } ] }';
    const configuredTwo = 'Registry.{ { 1001 1002 1003 100000 } [ { billing https://fixture.invalid/billing [ { balance «#balance» } { usage «#usage» } { pending «#pending» } ] } ] }';
    const dependencies = transport => ({ env: { XDG_CONFIG_HOME: '/fixture/config' }, home: '/fixture/home', readFile: filename => { assert.equal(filename, '/fixture/config/browser-read/registry.datom'); return configured; }, transport });
    let completed = 0;
    async function test(name, action) {
      try { await action(); ++completed; }
      catch (error) { throw new Error(name, { cause: error }); }
    }
    function fakePage(options = {}) {
      const events = [];
      const tab = {
        setDefaultTimeout: timeout => events.push(['timeout', timeout]),
        goto: async (address, settings) => { events.push(['goto', address, settings]); if (options.navigationFailure) throw new Error('RAW PAGE NEVER PRINT'); },
        locator: selector => ({
          count: async () => options.counts?.[selector] ?? 1,
          innerText: async () => { if (options.failFields?.includes(selector)) throw new Error('RAW PAGE NEVER PRINT'); return options.values?.[selector] ?? 'fixture text'; }
        }),
        close: async settings => { events.push(['close', settings]); if (options.closeFailure) throw new Error('RAW PAGE NEVER PRINT'); }
      };
      const page = { context: () => ({ newPage: async () => { events.push(['open']); if (options.openFailure) throw new Error('RAW PAGE NEVER PRINT'); return tab; } }) };
      return { page, events };
    }
    async function main() {
      await test('codec guillemets and backslashes', () => {
        for (const value of ['white space', 'a»b«c', 'a\\b', 'literal\\q', 'first\nsecond', 'αβ']) {
          const decoded = reader.request('Read.{ ' + reader.quoted(value) + ' [ field ] }');
          assert.equal(decoded.page, value);
        }
        assert.equal(reader.request('Read.{ «a«b»c» [ field ] }').page, 'a«b»c');
        assert.throws(() => reader.request('Read.{ page [ field field ] }'));
        assert.throws(() => reader.request('Read.{ page [] }'));
        assert.throws(() => reader.request('Read.{ page [ field ] } extra'));
        assert.throws(() => reader.request('Other.{ page [ field ] }'));
      });
      await test('runtime-only registry and limits', () => {
        const parsed = reader.registry(configuredTwo);
        assert.deepEqual(parsed.limits, { navigationMs: 1001, actionMs: 1002, commandMs: 1003, outputBytes: 100000 });
        assert.equal(parsed.pages[0].fields[0].locator, '#balance');
        for (const text of [configured.replace('1001', '0'), configured.replace('1001', '-1'), configured.replace('https:', 'file:'), configured.replace('{ balance «#balance» }', '{ balance «#balance» } { balance «#again» }')]) assert.throws(() => reader.registry(text));
      });
      await test('values only and requested ordering', () => {
        const deps = dependencies(task => { assert.deepEqual(task.fields, [{ name: 'balance', locator: '#balance' }]); return { kind: 'Values', values: [['balance', 'requested value']] }; });
        assert.equal(reader.encode(reader.run('Read.{ billing [ balance ] }', deps)), 'Values.[ { «balance» «requested value» } ]');
        deps.transport = () => ({ kind: 'Values', values: [['balance', 'requested value'], ['unrequested', 'RAW PAGE NEVER PRINT']] });
        assert.equal(reader.encode(reader.run('Read.{ billing [ balance ] }', deps)), 'Refused.BrowserOutcome');
      });
      await test('missing unreadable and invalid registry exact path', () => {
        for (const [code, expected] of [['ENOENT', 'MissingRegistry'], ['EACCES', 'UnreadableRegistry']]) {
          const deps = dependencies(() => { throw new Error('must not attach'); });
          deps.readFile = () => { const error = new Error('RAW SECRET NEVER PRINT'); error.code = code; throw error; };
          assert.equal(reader.encode(reader.run('Read.{ billing [ balance ] }', deps)), 'Refused.' + expected + '.«/fixture/config/browser-read/registry.datom»');
        }
        const deps = dependencies(() => { throw new Error('must not attach'); });
        deps.readFile = () => 'invalid';
        assert.equal(reader.run('Read.{ billing [ balance ] }', deps).reason, 'InvalidRegistry');
        deps.env.XDG_CONFIG_HOME = 'relative';
        assert.equal(reader.run('Read.{ billing [ balance ] }', deps).reason, 'ConfigurationDirectory');
        delete deps.env.XDG_CONFIG_HOME;
        deps.readFile = filename => { assert.equal(filename, '/fixture/home/.config/browser-read/registry.datom'); return configured; };
        assert.equal(reader.run('Read.{ unknown [ balance ] }', deps).reason, 'UnknownPage');
      });
      await test('unknown names refuse before transport', () => {
        const deps = dependencies(() => { throw new Error('must not attach'); });
        assert.equal(reader.run('Read.{ unknown [ balance ] }', deps).reason, 'UnknownPage');
        assert.deepEqual(reader.run('Read.{ billing [ unknown other ] }', deps).detail, ['unknown', 'other']);
        assert.equal(reader.run('Read.{ billing [] }', deps).reason, 'InvalidRequest');
      });
      await test('one tab closes after successful text read', async () => {
        const fixture = fakePage({ values: { '#balance': 'text «quoted»\nsecond' } });
        const task = { address: 'https://fixture.invalid', fields: [{ name: 'balance', locator: '#balance' }], limits: { navigationMs: 23, actionMs: 41 } };
        const result = await reader.readTab(fixture.page, task);
        assert.deepEqual(result, { kind: 'Values', values: [['balance', 'text «quoted»\nsecond']] });
        assert.equal(fixture.events.filter(event => event[0] === 'open').length, 1);
        assert.equal(fixture.events.filter(event => event[0] === 'close').length, 1);
        assert.equal(fixture.events.find(event => event[0] === 'goto')[2].timeout, 23);
      });
      await test('ALL missing fields and NO partial values', async () => {
        const fixture = fakePage({ counts: { '#usage': 0, '#pending': 2 } });
        const task = { ...reader.registry(configuredTwo).pages[0], limits: reader.registry(configuredTwo).limits };
        const result = await reader.readTab(fixture.page, task);
        assert.deepEqual(result, { kind: 'Refused', reason: 'MissingFields', detail: ['usage', 'pending'] });
        assert(!reader.encode(result).includes('fixture text'));
        assert.equal(fixture.events.filter(event => event[0] === 'close').length, 1);
      });
      await test('navigation extraction and cleanup failures stay typed', async () => {
        const task = { ...reader.registry(configuredTwo).pages[0], limits: reader.registry(configuredTwo).limits };
        for (const [options, reason] of [[{ navigationFailure: true }, 'Navigation'], [{ closeFailure: true }, 'TabCleanup'], [{ openFailure: true }, 'TabOpen']]) {
          const fixture = fakePage(options);
          const result = await reader.readTab(fixture.page, task);
          assert.equal(result.reason, reason);
          assert.equal(fixture.events.filter(event => event[0] === 'close').length, options.openFailure ? 0 : 1);
          assert(!reader.encode(result).includes('RAW PAGE'));
        }
        const fixture = fakePage({ failFields: ['#balance', '#usage', '#pending'] });
        assert.deepEqual((await reader.readTab(fixture.page, task)).detail, ['balance', 'usage', 'pending']);
      });
      await test('wrapper bridge fake lifecycle and suppressed CLI envelope', () => {
        const original = childProcess.spawnSync;
        const task = { address: 'https://fixture.invalid', fields: [{ name: 'balance', locator: '#balance' }], limits: { navigationMs: 23, actionMs: 41, commandMs: 82, outputBytes: 9000 } };
        for (const failure of [undefined, 'attach', 'run-code', 'detach']) {
          const calls = [];
          let directory;
          childProcess.spawnSync = (executable, args, settings) => {
            assert.equal(executable, '/fake/wrapper');
            assert.equal(settings.timeout, 82); assert.equal(settings.maxBuffer, 9000);
            directory = settings.cwd;
            assert(args[1].startsWith('-s=browser-read-'));
            const command = args[2]; calls.push(command);
            if (command === failure) return { status: 1, stdout: 'RAW SECRET NEVER PRINT', stderr: 'RAW PAGE NEVER PRINT' };
            const result = command === 'run-code' ? { result: JSON.stringify({ kind: 'Values', values: [['balance', 'requested value']] }), snapshot: 'RAW PAGE NEVER PRINT' } : { status: 'done', result: { snapshot: 'RAW PAGE NEVER PRINT' } };
            return { status: 0, stdout: JSON.stringify(result), stderr: 'RAW SECRET NEVER PRINT' };
          };
          try {
            const result = reader.wrapperTransport('/fake/wrapper', task);
            assert.equal(result.kind, failure ? 'Refused' : 'Values');
            assert.equal(calls[0], 'attach'); assert.equal(calls.at(-1), 'detach');
            assert.equal(calls.filter(command => command === 'run-code').length, failure === 'attach' ? 0 : 1);
            assert(!fs.existsSync(directory));
            assert(!reader.encode(result).includes('RAW'));
          } finally { childProcess.spawnSync = original; }
        }
      });
      process.stdout.write('browser-read synthetic groups passed: ' + completed + '\n');
    }
    main().catch(error => { console.error(error); process.exitCode = 1; });
  '';
in
pkgs.runCommand "browser-read-contract" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
  node --check ${browserRead}
  node ${tests} ${browserRead}
  touch "$out"
''
