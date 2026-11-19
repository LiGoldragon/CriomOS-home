# Browser read

Owned development: flow 629113, branch `flow/629113-browser-read`. Candidate only; synthetic evidence is not live-session acceptance. The wrapper/profile owner integrates this package with the reviewed `playwrightChrome` package; this package never constructs a second wrapper.

`browser-read 'Read.{ page [ field ... ] }'` reads the registry anew from `$XDG_CONFIG_HOME/browser-read/registry.datom` (otherwise `$HOME/.config/browser-read/registry.datom`). The request/result and registry use datom-codec. Successful output is `Read.[ { field value } ... ]` in request order; failure is `Refused.<phase>` with configured field names where relevant. No partial values accompany failure.

Registry shape (synthetic example, not installed account defaults):

```datom
Registry.{ { 1000 1000 10000 2000 65536 }
           [ { fixture https://fixture.invalid/
               [ { title h1 } { remaining .remaining } ] } ] }
```

The limits, in order, are navigation milliseconds, locator/action milliseconds, complete read command milliseconds, each cleanup wait milliseconds, and maximum wrapper/output bytes. Page names, URLs, fields, locators and limits are runtime data. Extraction is text from exactly one matching locator; there is no free-form action or JavaScript input.

The Rust frontend owns typed text and requested-only output validation. `session.py` uses only Python's standard library and the reviewed wrapper. The fixed `read-page.cjs` is code passed through that wrapper, with registry values JSON-encoded as data. It opens its own page, bounds navigation/locator operations, and closes then observes `isClosed` while connected. A broken or timed-out read receives a cleanup refusal, never successful values. The helper is a Linux child subreaper, owns its frontend/daemon descendants, and observes their exit through pidfds rather than a detach acknowledgement. Every read has a new session and a private temporary tree for global configuration, daemon state, cache, output and subprocess temporary data. Unreviewed inherited Playwright/global/init-script settings are excluded; the wrapper alone handles the token.

Unknown until separately authorized live evidence: extension disconnect behavior, auxiliary browser-owned tabs/popups/downloads, and real bridge ordering. No synthetic fixture establishes those facts. A failed/unconfirmed tab cleanup can leave an owned browser tab; the refusal explicitly preserves that uncertainty. This command does not restart Chrome or act on accounts.
