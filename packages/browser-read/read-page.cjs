'use strict';

// Generated code is fixed here. Registry strings enter only through JSON data.
async function readPage(page, task) {
  const context = page.context();
  let tab;
  let creating = false;
  let timedOut = false;
  let output;
  const bounded = (promise, milliseconds) => new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('Timeout')), milliseconds);
    Promise.resolve(promise).then(value => { clearTimeout(timer); resolve(value); }, error => { clearTimeout(timer); reject(error); });
  });
  const connected = () => context.browser()?.isConnected() === true;
  try {
    creating = true;
    const creation = context.newPage().then(created => {
      tab = created;
      context.__browserReadOwnedPage = { marker: task.marker, tab };
      return tab;
    });
    try { await bounded(creation, task.limits.action_ms); }
    catch { timedOut = true; throw new Error('TabOpen'); }
    creating = false;
    tab.setDefaultTimeout(task.limits.action_ms);
    try {
      await bounded(tab.goto(task.url, { timeout: task.limits.navigation_ms, waitUntil: 'domcontentloaded' }), task.limits.navigation_ms);
    } catch { output = { phase: 'Refused', refusal: 'Navigation' }; }
    if (!output) {
      const values = [], missing = [];
      for (const field of task.fields) {
        try {
          const locator = tab.locator(field.locator);
          if (await bounded(locator.count(), task.limits.action_ms) !== 1) { missing.push(field.name); continue; }
          const value = await bounded(locator.innerText({ timeout: task.limits.action_ms }), task.limits.action_ms);
          if (typeof value !== 'string') { missing.push(field.name); continue; }
          values.push({ name: field.name, value });
        } catch { missing.push(field.name); }
      }
      output = missing.length ? { phase: 'Refused', refusal: { Fields: missing } } : { phase: 'Read', values };
    }
  } catch { output = { phase: 'Refused', refusal: 'TabOpen' }; }
  finally {
    let closed = !creating && !tab && connected();
    if (tab) {
      try {
        await bounded(tab.close({ runBeforeUnload: false }), task.limits.cleanup_ms);
        closed = tab.isClosed() === true && connected();
      } catch { closed = false; }
    }
    // A timed-out newPage may still produce a tab: it is never a confirmed read.
    if (!closed || timedOut) output = { phase: 'Refused', refusal: 'TabCleanup' };
  }
  return output;
}

async function closeOwnedPage(page, task) {
  const context = page.context();
  const owned = context.__browserReadOwnedPage;
  if (!owned || owned.marker !== task.marker) return { closed: false };
  let timer;
  try {
    await Promise.race([
      owned.tab.close({ runBeforeUnload: false }),
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Timeout')), task.limits.cleanup_ms); })
    ]);
    return { closed: owned.tab.isClosed() === true && context.browser()?.isConnected() === true };
  } catch { return { closed: false }; }
  finally { clearTimeout(timer); }
}

module.exports = { readPage, closeOwnedPage };
