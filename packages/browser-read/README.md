# Browser read

Owned development: flow 629113, branch `flow/629113-browser-read`. This package is the reader side of the agreed `read-session` contract. The wrapper owner integrates the configured, reviewed `playwrightChrome` package; Field owns activation. Synthetic evidence establishes the reader boundary, not a running browser route.

`browser-read 'Read.{ page [ field ... ] }'` reads the registry anew from `$XDG_CONFIG_HOME/browser-read/registry.datom` (otherwise `$HOME/.config/browser-read/registry.datom`). The request/result and registry use datom-codec. Successful output is `Read.[ { field value } ... ]` in request order; failure is `Refused.<phase>` with configured field names where relevant. No partial values accompany failure.

Registry shape (synthetic example, not installed account defaults):

```datom
Registry.{ { 1000 1000 10000 2000 65536 }
           [ { fixture https://fixture.invalid/
               [ { title h1 } { remaining .remaining } ] } ] }
```

The limits, in order, are navigation milliseconds, locator/action milliseconds, complete operational deadline milliseconds, each wrapper cleanup wait milliseconds, and maximum wrapper/output bytes. The navigation/action/Page-cleanup waits fit the driver’s signed-32-bit millisecond timer. Page names, HTTP(S) URLs, fields, locators and limits are runtime data. Extraction is text from exactly one matching locator. The request contains configured names alone.

## Wrapper boundary

The Rust frontend invokes `playwright-chrome read-session` once, with one JSON object on stdin:

```json
{"readCode":"internally generated async Page function","limits":{"navigation_ms":1000,"action_ms":1000,"command_ms":10000,"cleanup_ms":2000,"output_bytes":65536}}
```

The reader's fixed function is compiled from `frontend/src/read-page.cjs`; registry values enter it through JSON data. It opens its own Page, bounds navigation and locator operations, and closes then observes `isClosed` while connected. It returns a serialized `Read` or page-phase refusal. An unconfirmed Page cleanup stays a refusal.

The wrapper owns token preflight, private configuration/session/output/temporary artifacts, attach/run-code/detach, and all processes/scopes it starts, on every path. Its terminal stdout is exactly `{"result":"serialized read return"}` on success, or `{"isError":true,"phase":"SessionAttach|SessionRun|SessionCleanup|ArtifactSetup|ArtifactCleanup|Interrupted"}` with one actual phase string. It completes owned process/artifact cleanup before replying. The reader waits for this terminal reply and neither receives a daemon handle nor terminates daemons or performs artifact cleanup. Native error and snapshot content stay inside the wrapper. Values with a nonzero exit are refused; a recognized typed failure, including a Page-phase failure returned in result, is accepted regardless of exit status.

The extraction return is `{"phase":"Read","values":[{"name":"configured field","value":"text"}]}` or `{"phase":"Refused","refusal":"TabOpen|Navigation|TabCleanup"}` (one actual phase), or `{"phase":"Refused","refusal":{"Fields":["configured field"]}}`. The reader validates exact result shapes, field membership/order/count, and absence of partial values.

This boundary was agreed with Mind nixCriomos Sol (stmf), following Psyche 6sll: wrapper process ownership replaces the unaccepted reader-side session/subreaper prototype. The installed older wrapper has no `read-session` capability; integration requires the wrapper owner's new immutable implementation and tests. Existing attach JSON alone establishes a PID only after successful startup, and supplies no failed-start ownership handoff. The reader makes no claim about that superseded mechanism.

Unknown until separately authorized live evidence: extension detach/Chrome preservation, browser-owned auxiliary tabs/popups/downloads, and real bridge ordering. No browser/account/credential test is included in this reader check. The wrapper's process/artifact lifecycle has its own synthetic acceptance, owned by its implementer.
