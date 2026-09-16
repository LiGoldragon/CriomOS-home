# cf7879 cluster-relay activation

Import `modules/home/deployments/cf7879-cluster-relay.nix` in the selected
Home deployment and set `criomosHome.clusterRelay.enable = true`. The package
then exposes `cluster-relay FIRST-SIX-WORDS LAST-SIX-WORDS`; its existing
`FLOW_ID` selects the fixed session and transcript mapping.

The default route file deliberately marks all three members `unknown`. The
Message relay returns an unavailable outcome and opens no adapter endpoint.
This is the only safe setting before a living confirmation and a fresh
readiness witness.

For one confirmed attempt, the deployment sets
`criomosHome.clusterRelay.runtimeRouteFile = "/run/user/1001/flow/cluster-relay-routes.json"`.
The Flow owner atomically replaces that mode-0600, user-owned file for the
attempt and removes it afterwards. A Claude row may be `harness: claude, readiness: idle` only
after that attempt's `claude agents --json` shows one PID-live target with
`status: idle` and without `state: blocked`, `waitingFor: permission prompt`,
or an equivalent permission-waiting field. The pinned prompt-relay repeats
those checks before it attaches and pastes.

A busy row is `harness: nexus, readiness: busy` with the newly activated
Message v0.12 FlowDeliver socket as its endpoint. It is a parking receipt,
not a recipient receipt, and it must be used only after the activated daemon
is confirmed to speak the pinned FlowDeliver wire and Flow confirms the
target name. No file supplies a guessed busy route or a live Flow registry.

The route file is single-attempt state: the owner removes it or restores the
unknown-only route configuration after the attempt. This proposal has no
automatic freshness clock; leaving a readiness file in place is a manual
operational risk, not a current guarantee.

Example fresh route file, where `${PROMPT_RELAY}` is the deployed
`prompt-relay` program from the pinned Home generation:

```json
{"routes":[
 {"flow_identifier":"cf7879","session_identifier":"01a0a715-2d5d-7342-b278-1dbcf78795bd","harness":"codex","readiness":"unknown","endpoint":"/home/li/.codex/app-server-control/app-server-control.sock"},
 {"flow_identifier":"efa157","session_identifier":"efa15708-dc5d-42ce-af62-8ffb84c9815e","harness":"claude","readiness":"idle","endpoint":"${PROMPT_RELAY}"},
 {"flow_identifier":"57a7aa","session_identifier":"57a7aa02-e52d-4266-8746-6770ff770d11","harness":"claude","readiness":"idle","endpoint":"${PROMPT_RELAY}"}
]}
```

If Flow has freshly witnessed a member busy and the activated Message 0.12
daemon is confirmed compatible, replace only that member's row with
`{"harness":"nexus","readiness":"busy","endpoint":"/run/user/1001/message/message.sock"}`
while retaining its exact flow and session identifiers. The FlowDeliver
result parks work; it does not prove a recipient has seen it.
