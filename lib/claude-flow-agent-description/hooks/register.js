const passageStart = "A fresh agent costs more than it looks.";
const passageEnd = "When in doubt, don't spawn.";

export function register(on) {
  on('tool.describe', { tool: 'Agent' }, async ($, event, next) => {
    if (event.provider?.plugin !== 'engine' || event.provider?.tier !== 'core') {
      return next(event);
    }
    if (!await $.env.get('FLOW_ID')) return next(event);

    const { description } = event;
    const start = description.indexOf(passageStart);
    const end = description.indexOf(passageEnd);
    if (
      start < 0 || end < start + passageStart.length ||
      description.lastIndexOf(passageStart) !== start ||
      description.lastIndexOf(passageEnd) !== end
    ) return next(event);

    let replacement;
    try {
      replacement = await $.fs.read(`${$.plugin.root}/agent-description.txt`);
    } catch {
      return next(event);
    }
    if (typeof replacement !== 'string' || replacement.length === 0) return next(event);
    return {
      description: description.slice(0, start) + replacement + description.slice(end + passageEnd.length),
      ...(event.isDeferred === undefined ? {} : { isDeferred: event.isDeferred }),
    };
  });
}
