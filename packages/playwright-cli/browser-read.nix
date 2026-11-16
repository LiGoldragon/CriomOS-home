{ pkgs }:
pkgs.writeText "browser-read.cjs" ''
  'use strict';
  const fs = require('node:fs');
  const path = require('node:path');
  const os = require('node:os');
  const crypto = require('node:crypto');
  const childProcess = require('node:child_process');

  // A schema-bound datom codec: only strings, positional structs and vectors.
  // Variant roots are composed separately; no caller code is evaluated.
  function decode(source, variant) {
    let position = 0;
    function space() {
      while (position < source.length) {
        if (/\s/.test(source[position])) { ++position; continue; }
        if (source[position] === ';') {
          while (position < source.length && source[position] !== '\n') ++position;
          continue;
        }
        break;
      }
    }
    function value() {
      space();
      const first = source[position++];
      if (first === '{' || first === '[') {
        const end = first === '{' ? '}' : ']';
        const items = [];
        space();
        while (source[position] !== end) {
          if (position >= source.length) throw new Error('Unclosed');
          items.push(value()); space();
        }
        ++position;
        return { kind: first === '{' ? 'Struct' : 'Vector', items };
      }
      if (first === '«') {
        let text = "", depth = 1;
        while (position < source.length) {
          const character = source[position++];
          if (character === '\\' && ['\\', '«', '»'].includes(source[position])) {
            text += source[position++]; continue;
          }
          if (character === '«') ++depth;
          if (character === '»') { if (--depth === 0) return text; }
          text += character;
        }
        throw new Error('UnclosedString');
      }
      if (!first || /[\s{}\[\]«»();]/.test(first)) throw new Error('String');
      let text = first;
      while (position < source.length && !/[\s{}\[\]«»();]/.test(source[position])) text += source[position++];
      return text;
    }
    space();
    const prefix = variant + '.';
    if (!source.startsWith(prefix, position)) throw new Error('Variant');
    position += prefix.length;
    const result = value();
    space();
    if (position !== source.length) throw new Error('Trailing');
    return result;
  }
  function positions(node, kind, count) {
    if (!node || node.kind !== kind || (count !== undefined && node.items.length !== count)) throw new Error('Shape');
    return node.items;
  }
  function string(value) {
    if (typeof value !== 'string' || value.length === 0) throw new Error('Name');
    return value;
  }
  function unique(values) { if (new Set(values).size !== values.length) throw new Error('Duplicate'); }
  function request(source) {
    const [page, fields] = positions(decode(source, 'Read'), 'Struct', 2);
    const names = positions(fields, 'Vector').map(string);
    if (!names.length) throw new Error('EmptyFields');
    unique(names);
    return { page: string(page), fields: names };
  }
  function registry(source) {
    const [limitsNode, pagesNode] = positions(decode(source, 'Registry'), 'Struct', 2);
    const numbers = positions(limitsNode, 'Struct', 4).map(number => {
      if (typeof number !== 'string' || !/^[1-9][0-9]*$/.test(number)) throw new Error('Limit');
      const parsed = Number(number);
      if (!Number.isSafeInteger(parsed)) throw new Error('Limit');
      return parsed;
    });
    const pages = positions(pagesNode, 'Vector').map(node => {
      const [name, address, fieldsNode] = positions(node, 'Struct', 3);
      const url = new URL(string(address));
      if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Address');
      const fields = positions(fieldsNode, 'Vector').map(field => {
        const [fieldName, locator] = positions(field, 'Struct', 2);
        return { name: string(fieldName), locator: string(locator) };
      });
      unique(fields.map(field => field.name));
      return { name: string(name), address, fields };
    });
    unique(pages.map(page => page.name));
    return { limits: { navigationMs: numbers[0], actionMs: numbers[1], commandMs: numbers[2], outputBytes: numbers[3] }, pages };
  }
  function quoted(text) {
    return '«' + text.replaceAll('\\', '\\\\').replaceAll('«', '\\«').replaceAll('»', '\\»') + '»';
  }
  function refused(reason, detail) { return { kind: 'Refused', reason, detail }; }
  function encode(result) {
    if (result.kind === 'Values') return 'Values.[ ' + result.values.map(([name, text]) => '{ ' + quoted(name) + ' ' + quoted(text) + ' }').join(' ') + ' ]';
    const prefix = 'Refused.' + result.reason;
    if (Array.isArray(result.detail)) return prefix + '.[ ' + result.detail.map(quoted).join(' ') + ' ]';
    return result.detail === undefined ? prefix : prefix + '.' + quoted(result.detail);
  }

  // This function is serialized into the existing wrapper's run-code call.
  // It owns only its newly opened tab, and never executes request/registry code.
  async function readTab(page, task) {
    let tab, result;
    try {
      tab = await page.context().newPage();
      tab.setDefaultTimeout(task.limits.actionMs);
      await tab.goto(task.address, { timeout: task.limits.navigationMs, waitUntil: 'domcontentloaded' });
      const values = [], missing = [];
      for (const field of task.fields) {
        try {
          const locator = tab.locator(field.locator);
          if (await locator.count() !== 1) { missing.push(field.name); continue; }
          values.push([field.name, await locator.innerText({ timeout: task.limits.actionMs })]);
        } catch { missing.push(field.name); }
      }
      result = missing.length ? { kind: 'Refused', reason: 'MissingFields', detail: missing } : { kind: 'Values', values };
    } catch { result = { kind: 'Refused', reason: tab ? 'Navigation' : 'TabOpen' }; }
    finally {
      if (tab) {
        try { await tab.close({ runBeforeUnload: false }); }
        catch { result = { kind: 'Refused', reason: 'TabCleanup' }; }
      }
    }
    return result;
  }

  function wrapperTransport(wrapper, task) {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'browser-read-'));
    const session = 'browser-read-' + crypto.randomUUID();
    let result;
    fs.mkdirSync(path.join(directory, '.playwright'));
    const configuration = path.join(directory, 'cli.json');
    fs.writeFileSync(configuration, JSON.stringify({ outputDir: path.join(directory, 'output'), timeouts: { action: task.limits.actionMs, navigation: task.limits.navigationMs }, saveSession: false, codegen: 'none' }), { mode: 0o600 });
    function invoke(argumentsList) {
      const child = childProcess.spawnSync(wrapper, ['--json', '-s=' + session, ...argumentsList], {
        cwd: directory, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
        timeout: task.limits.commandMs, maxBuffer: task.limits.outputBytes
      });
      if (child.error || child.status !== 0) throw new Error('Wrapper');
      const output = JSON.parse(child.stdout);
      if (!output || output.isError || output.result?.isError) throw new Error('Wrapper');
      return output;
    }
    try {
      invoke(['attach', '--extension=chrome', '--config=' + configuration]);
      const code = 'async page => (' + readTab.toString() + ')(page,' + JSON.stringify(task) + ')';
      const output = invoke(['run-code', code]);
      if (typeof output.result !== 'string') throw new Error('Outcome');
      result = JSON.parse(output.result);
    } catch { result = refused('Browser'); }
    finally {
      try { invoke(['detach']); }
      catch { result = refused('SessionCleanup'); }
      try { fs.rmSync(directory, { recursive: true, force: true }); }
      catch { result = refused('ArtifactCleanup'); }
    }
    return result;
  }
  function validateOutcome(outcome, fields) {
    if (outcome?.kind === 'Values' && Array.isArray(outcome.values) && outcome.values.length === fields.length && outcome.values.every((entry, index) => Array.isArray(entry) && entry.length === 2 && entry[0] === fields[index] && typeof entry[1] === 'string')) return outcome;
    const reasons = ['TabOpen', 'Navigation', 'TabCleanup', 'Browser', 'SessionCleanup', 'ArtifactCleanup'];
    if (outcome?.kind === 'Refused' && reasons.includes(outcome.reason) && outcome.detail === undefined) return refused(outcome.reason);
    if (outcome?.kind === 'Refused' && outcome.reason === 'MissingFields' && Array.isArray(outcome.detail) && outcome.detail.length && new Set(outcome.detail).size === outcome.detail.length && outcome.detail.every(name => fields.includes(name))) return refused('MissingFields', outcome.detail);
    return refused('BrowserOutcome');
  }
  function run(source, dependencies) {
    let wanted;
    try { wanted = request(source); } catch { return refused('InvalidRequest'); }
    const configurationDirectory = dependencies.env.XDG_CONFIG_HOME || path.join(dependencies.home, '.config');
    if (!path.isAbsolute(configurationDirectory)) return refused('ConfigurationDirectory', configurationDirectory);
    const filename = path.resolve(configurationDirectory, 'browser-read', 'registry.datom');
    let text;
    try { text = dependencies.readFile(filename); }
    catch (error) { return refused(error.code === 'ENOENT' ? 'MissingRegistry' : 'UnreadableRegistry', filename); }
    let configured;
    try { configured = registry(text); } catch { return refused('InvalidRegistry', filename); }
    const page = configured.pages.find(item => item.name === wanted.page);
    if (!page) return refused('UnknownPage', wanted.page);
    const unknown = wanted.fields.filter(name => !page.fields.some(field => field.name === name));
    if (unknown.length) return refused('UnknownFields', unknown);
    const task = { address: page.address, fields: wanted.fields.map(name => page.fields.find(field => field.name === name)), limits: configured.limits };
    try { return validateOutcome(dependencies.transport(task), wanted.fields); }
    catch { return refused('Browser'); }
  }
  function main(argumentsList) {
    const [wrapper, source] = argumentsList;
    let result;
    if (argumentsList.length !== 2) result = refused('InvalidRequest');
    else result = run(source, { env: process.env, home: os.homedir(), readFile: filename => fs.readFileSync(filename, 'utf8'), transport: task => wrapperTransport(wrapper, task) });
    process.stdout.write(encode(result) + '\n');
    process.exitCode = result.kind === 'Values' ? 0 : 1;
  }
  module.exports = { decode, quoted, request, registry, encode, readTab, validateOutcome, run, wrapperTransport, main };
  if (require.main === module) main(process.argv.slice(2));
''
