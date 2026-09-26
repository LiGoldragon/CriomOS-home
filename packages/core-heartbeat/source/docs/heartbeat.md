# Core heartbeat proposal

One bounded tick for core e43002. No repairs, restarts, settings edits or activation.

The systemd source polls every five minutes; persisted lastRun plus the latest
valid account.primary weekly quota gates the Luna job. At >=50% left:15 minutes,
>=20:30, >=5:60, else120. Missing/stale (>120 minutes) quota falls back to60.
Future/invalid readings and other provider/windows are excluded. The event log
records interval and reason. flock serializes CLI runs; atomic state replacement
avoids stale PID locks. No installed unit is changed.

Configured lane bookmarks are read by jj --ignore-working-copy. Peer reports
and structured last user records are bounded reads, with unavailable status
explicit. These are local bookmark observations, not an automatic remote fetch.
The collector supports ordinary Claude content strings/arrays and Codex rollout
response_item/event_msg user turns; it never treats assistant text as user text.
An overlarge record outside the bounded tail can be unavailable.

Luna receives the curated snapshot and prior receipts. It selects a known major
enum, source candidate ID and allowlisted recipients. Code validates these and
constructs the message; it never executes model-proposed commands. The custom
base/no-environment adapter is separate in heartbeat-luna.mjs.

Delivery uses codex queue --thread UUID --message TEXT or the existing
prompt-relay Claude idle gate. Acceptance requires recognized transport output,
not exit zero alone. Recipient transcript matching can upgrade acceptance to
transcript_witnessed. FileOnly is separate from recipient delivery. Accepted
recipients are not resent; pending recipients can retry. Each acceptance is
persisted before the next target; a crash between send and state commit remains
ambiguous, so exactly-once delivery is not claimed. JSON heartbeat v1 is a
validated prototype contract, not a generated Ethos/datom contract; replacing
the existing prompt-relay JSON envelope remains separate order10 work.

A source candidate and enum determine event identity; model prose does not.
One major event may be sent per tick. The report lists actual receipt kinds
and routes; the outgoing message includes prior receipts and its report path
because future delivery receipts cannot truthfully be known at send time.
State/report retention and remote bookmark freshness remain production policy.

Run node --test tools/heartbeat.test.mjs or the heartbeat-fixtures Nix check.
Fixture process tests are local boundary proofs, not live Claude/Codex delivery
or a real model call. Those need separate receipts. Example configuration lists
the existing cluster; secondary supplies active paths and enables the unit.
