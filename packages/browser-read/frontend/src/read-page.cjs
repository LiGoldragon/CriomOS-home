'use strict';

// Generated code is fixed here. Registry strings enter only through JSON data.
async function readPage(page, task) {
  const context = page.context();
  let tab;
  let creating = false;
  let unconfirmedCreation = false;
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
      return tab;
    });
    try { await bounded(creation, task.limits.action_ms); }
    catch { unconfirmedCreation = true; throw new Error('TabOpen'); }
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
    // An unconfirmed newPage may still produce a tab: it is never a confirmed read.
    if (!closed || unconfirmedCreation) output = { phase: 'Refused', refusal: 'TabCleanup' };
  }
  return output;
}

module.exports = { readPage };
