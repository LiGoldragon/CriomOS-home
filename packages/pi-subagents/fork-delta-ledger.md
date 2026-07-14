# Pi-subagents fork delta ledger

## Scope and state

This ledger reconciles the historical CriomOS-home package at `pi-subagents` 0.31.0 with upstream 0.34.0. It records evidence; it does not change the effective package version or activate a system.

The retained reconciliation witness is `reconciliation/0.31.0-to-0.34.0.patch`, SHA-256 `0427ab1331dc35cfb2af82ecf489e55c406a7b8f05b8a2090e4413e0fc414291`. `reconciliation/verify-0.34.0.sh` materializes both trees and executes every gate; `0.34.0.nix` builds the candidate and `0.34.0-check.nix` is the Nix package-content and Pi-load witness. All decisions remain **provisional** because the raw reconciled full-suite exit is 1, even though the same three failures occur on pristine upstream. Targeted delta tests and the Nix check pass.

## Candidate and provenance

| Field | Immutable identity or source path |
|---|---|
| Canonical upstream | `https://github.com/nicobailon/pi-subagents` |
| Packaged base | npm 0.31.0, Git commit `e4f06282d0c95856b36b7ec2893f4fd294ebfefe`, registry integrity `sha512-ffzM8T4rXb1jmlSfrjD5l9xv3KS4vH069Cka14LCbDw8bJxuB/HRd3QnQfSB0z61+cZO9Aq8M1eq3FdKVvCSPg==` |
| Historical package snapshot | CriomOS-home commit `8a6c5b154f7df63b65c6027ba41ea7c6496d60db`, `packages/pi-subagents/default.nix` and its six sibling patch files |
| Historical lock identity | `flake.lock` node `pi-subagents-src`, NAR `sha256-EmDqAPVqJ6hxuA3Yj8SikM2kA/oI6D1QEe/gPvJbIVw=` |
| Update target | npm 0.34.0, Git commit `12a157d2a70b2f4cbc004c020c5f9213b6d8eea8`, registry integrity `sha512-JGgSYaieZ/2QtsW6BwSV1SX6zMz+YpV0JXUjSTtgphpk+z5OOJVJ4D/tWnCxIURXKcgsam+1vQkQgQ5fhrasFA==` |
| Target source hash | GitHub archive NAR `sha256-RN8f5cT/oRSkqwOAmvJ2uJsOmScYb0ijwixTd75iGHk=` |
| Reconciliation witnesses | `packages/pi-subagents/reconciliation/{verify-0.34.0.sh,0.34.0.nix,0.34.0-check.nix,0.34.0-applicability.txt,original-patches/}` |
| Rollback | Keep the effective package input and lock unchanged; no package-version or activation change is part of this evidence commit. |

The local fork was found by tracing the Home Manager package source through `packages/pi-subagents/default.nix`, the flake input and lock, and every package transform. The source input used the canonical npm name, but the derivation applied six local patches. Repository naming alone would have missed the fork.

## Original patch applicability

Each patch was recovered byte-for-byte from CriomOS-home commit `8a6c5b154f7df63b65c6027ba41ea7c6496d60db`. `reconciliation/0.34.0-applicability.txt` retains the per-hunk probe output. The command was run separately against an untouched checkout of upstream commit `12a157d2a70b2f4cbc004c020c5f9213b6d8eea8`:

```sh
patch --dry-run --forward --batch --verbose -d "$PRISTINE" -p1 < "$PATCH"
```

| Patch | SHA-256 | Exit and exact applicability evidence |
|---|---|---|
| `acceptance-read-only-evidence.patch` | `05b65361de58916d4a4954f557ef52a11c8e829e26fca1c488903b67bc7b3239` | exit 0; `acceptance.ts` hunk succeeded at 631; new test hunk succeeded at 1 |
| `agent-chain-clarify-opt-in.patch` | `82e58f0adba7c67eaebfd1906215a9d734876638126830070c24d511d488c4f9` | exit 1; schema hunk succeeded at 275 with offset 29; chain-execution hunk reported `Reversed (or previously applied)`, was skipped, and was ignored at 504 |
| `async-runner-stderr.patch` | `5aa8cc72c515b48e96ae96ff51f7e1a2721811d862d2891622276fba35c5ffbf` | exit 1; helper hunk succeeded at 277 with fuzz 1 and offset 62; spawn hunk failed at 266 |
| `detached-runner-peer-isolation.patch` | `6266f403b202fcf21d06d3ecd9bc523b355064527f8d3a8bcabf732e662ba404` | exit 1; both `utils.ts` hunks reported `Reversed (or previously applied)`, were skipped, and were ignored at 5 and 16 |
| `full-child-extension-bridge.patch` | `448ff81141a7ec5d3893de35670bffe3da5b523927b8aa2a0fd2c7197ee1b6f2` | exit 1; both intercom hunks reported reversed and were ignored at 238 and 365; `pi-args.ts` hunk succeeded at 141 with offset 16 |
| `slim-parent-skill.patch` | `ec9e95b42da359b89149a0221253d086e05e1a7731db304b47b81290a4aa6bcd` | exit 1; whole-skill hunk failed at 10 |

A reversed-patch message was never counted as successful application. The 0.31.0 control tree accepted all six patches in derivation order.

## Per-delta ledger

Every exact witness command below is retained in `reconciliation/verify-0.34.0.sh`. A witness command exits 0 only when the recorded pristine or reconciled result matches.

### Clarify is explicit opt-in

- **Rationale provenance:** CriomOS-home commit `1dd3f033b8b322c31609e1c56c4da4b99a62bc25`, `agent-chain-clarify-opt-in.patch`.
- **Local implementation:** `src/extension/schemas.ts` hunk `@@ -246,7 +246,7`; `src/runs/foreground/chain-execution.ts` hunk `@@ -504,7 +504,7`.
- **Upstream counterpart and status:** 0.34.0 already uses `clarify === true`, but retains ambiguous schema wording; `partially absorbed`.
- **Selected decision:** `reimplement` only the schema contract and drop the absorbed execution hunk.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness clarify pristine` and `reconciliation/verify-0.34.0.sh witness clarify reconciled`.
- **Pristine result:** command exit 0 after observing `clarify-code=0` and expected `clarify-schema=1`.
- **Reconciled result:** command exit 0 with `clarify-code=0` and `clarify-schema=0`; focused chain tests pass omitted-clarify and explicit-true cases.
- **Decision state:** `provisional`; raw reconciled full-suite exit is 1.

### Compact parent skill

- **Rationale provenance:** CriomOS-home commits `23665920be8e76c9029a546d1841654d68e39e54` and `60ed02dfbbd34bddef417abc2c75e5270b652959`.
- **Local implementation:** whole-file replacement in `skills/pi-subagents/SKILL.md`, original hunk `@@ -10,846 +10,127`.
- **Upstream counterpart and status:** 0.34.0 expands the runtime skill to 918 lines and does not preserve the compact local contract; `still absent`.
- **Selected decision:** `reimplement` the compact runtime skill against the target.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness compact-skill pristine` and `reconciliation/verify-0.34.0.sh witness compact-skill reconciled`.
- **Pristine result:** command exit 0 after observing expected `compact-skill=1 lines=918`.
- **Reconciled result:** command exit 0 with `compact-skill=0 lines=136` and required parent/child boundary phrases present.
- **Decision state:** `provisional`; raw reconciled full-suite exit is 1.

### Detached runner peer isolation

- **Rationale provenance:** CriomOS-home commit `6bf5e7ec700a00f33b19fe0c24d63e93f9ea61ce`.
- **Local implementation:** `src/shared/utils.ts` hunks removing the eager coding-agent import and optionalizing `resolveConfigDirName`.
- **Upstream counterpart and status:** 0.34.0 removes the eager import and adds package-root/package-json resolution; `fully absorbed`.
- **Selected decision:** `drop` the local patch.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness peer-isolation pristine` and `reconciliation/verify-0.34.0.sh witness peer-isolation reconciled`.
- **Pristine result:** command exit 0 with `peer-isolation=0`.
- **Reconciled result:** command exit 0 with unchanged `peer-isolation=0`; config-directory tests are included in the full run.
- **Decision state:** `provisional`; raw reconciled full-suite exit is 1 even though the same three failures exist upstream.

### Best-effort post-close stderr compaction

- **Rationale provenance:** CriomOS-home commits `60528d041c0ad784ba069781c17035ba9cafc5bc` and `f3fcf3e89b9448a5b99236415fe04fc207ddecd6`.
- **Local implementation:** `src/runs/background/async-execution.ts` helper hunk near old line 215 and spawn wiring near old line 238.
- **Upstream counterpart and status:** 0.34.0 captures `runner.stderr.log` and reads a bounded diagnostic tail, but does not compact the file; `partially absorbed`.
- **Selected decision:** `reimplement` only best-effort compaction after the detached process emits `close`.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness stderr-compaction pristine` and `reconciliation/verify-0.34.0.sh witness stderr-compaction reconciled`.
- **Pristine result:** command exit 0 after observing `stderr-capture=0` and expected `stderr-post-close-compaction=1`.
- **Reconciled result:** command exit 0 with both values 0; focused test `compacts detached runner stderr after close while retaining the tail` proves the helper retains the final 64 KiB after invocation.
- **Decision state:** `provisional`; this witness does **not** prove a live 64 KiB bound or guaranteed callback execution after parent exit, and raw reconciled full-suite exit is 1.

### Full child extension bridge

- **Rationale provenance:** CriomOS-home commit `bff854e76bf17457a201f643622ae3dc0334e2fe` and its child-argument harness witness.
- **Local implementation:** `src/intercom/intercom-bridge.ts` hunks near old lines 238 and 365; `src/runs/shared/pi-args.ts` hunk near old line 125.
- **Upstream counterpart and status:** 0.34.0 absorbs both intercom hunks through its native supervisor channel but still emits `--no-extensions`; `partially absorbed`.
- **Selected decision:** `reimplement` package-extension inheritance in `pi-args.ts` and drop the absorbed intercom hunks.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness child-extension pristine` and `reconciliation/verify-0.34.0.sh witness child-extension reconciled`.
- **Pristine result:** command exit 0 after observing expected `child-package-inheritance=1`.
- **Reconciled result:** command exit 0 with `child-package-inheritance=0`; two focused Pi-argument tests and the Nix Pi-load check pass.
- **Decision state:** `provisional`; raw reconciled full-suite exit is 1.

### Empty evidence for read-only acceptance

- **Rationale provenance:** CriomOS-home commit `df85cb32f687bb4dde1401d5cdfc6e75076c01f2` and its read-only acceptance tests.
- **Local implementation:** `src/runs/shared/acceptance.ts` hunk near old line 631 and new `test/unit/acceptance-read-only-evidence.test.ts`.
- **Upstream counterpart and status:** 0.34.0 requires non-empty change/test arrays for every run; `still absent`.
- **Selected decision:** `reimplement`; unchanged replay is rejected because it makes write-capable empty evidence pass.
- **Exact witness commands:** `reconciliation/verify-0.34.0.sh witness read-only-evidence pristine` and `reconciliation/verify-0.34.0.sh witness read-only-evidence reconciled`.
- **Pristine result:** command exit 0 after observing expected `read-only-evidence=1`.
- **Reconciled result:** command exit 0 with `read-only-evidence=0`; three focused tests prove empty read-only arrays pass, missing fields fail, and empty writer arrays fail.
- **Decision state:** `provisional`; raw reconciled full-suite exit is 1.

## Executed validation

### Targeted source and delta witnesses

The pristine/reconciled witness matrix returned:

| Witness | Pristine | Reconciled |
|---|---:|---:|
| explicit-clarify execution | 0 | 0 |
| explicit-clarify schema | 1 | 0 |
| compact parent skill | 1, 918 lines | 0, 136 lines |
| detached peer isolation | 0 | 0 |
| stderr capture | 0 | 0 |
| post-close stderr compaction | 1 | 0 |
| full child package-extension inheritance | 1 | 0 |
| read-only empty evidence | 1 | 0 |

`reconciliation/verify-0.34.0.sh focused` exited 0. Its raw Node test exit was 0: 108 tests, 108 passed, 0 failed.

### Upstream and reconciled test suites

`reconciliation/verify-0.34.0.sh full` ran `npm ci` and `npm run test:all` independently on both trees. The wrapper exited 0 only after verifying the exact known failure set, but it printed and retained both raw exits and marks the decisions provisional.

- Pristine upstream: raw exit 1; 981 tests; 978 passed; 3 failed.
- Reconciled: raw exit 1; 985 tests; 982 passed; 3 failed.
- The same three upstream tests fail in both trees: `sets the child intercom session name from env during agent startup`, `rewrites the final child-visible prompt through before_agent_start`, and `uses the fanout boundary through before_agent_start`. Each fails because the test double lacks `pi.registerTool` when `registerNativeSupervisorClient` runs.
- No new reconciliation-specific full-suite failure remains. The full-suite gate is still red, so this ledger does not call the package update complete.

### Nix package, contents, and Pi extension load

`reconciliation/verify-0.34.0.sh nix` builds the candidate and `0.34.0-check.nix`. The script printed `nix-package-content-rpc-check raw-exit=0` and exited 0. The fixed npm dependency identity is `sha256-IJJ3hceNvHUr5QFIa/+0tnxNiEPh7jifE9dvPHrLE58=`.

The Nix check verifies package name, version, extension metadata, runtime dependencies, compact skill, explicit-clarify logic, post-close stderr compaction, child extension inheritance, and read-only acceptance gating. It supplies the built coding-agent directory through `PI_PACKAGE_DIR`, loads the candidate extension through Pi RPC, rejects `Failed to load extension`, and requires a successful `get_commands` response.

### Complete retained command

```sh
packages/pi-subagents/reconciliation/verify-0.34.0.sh all
```

The complete command printed every pristine/reconciled component result, raw focused/full-suite/Nix exit status, and ended with `all-witnesses exit=0 decision-state=provisional`.

## Result

This is a mixed reconciliation across six deltas: one upstream-owned delta supports dropping its patch; the four originally identified remainder-analysis deltas require target-native remainder work; and the cleanly applicable acceptance patch separately requires target-native reimplementation because its old implementation regresses write-capable acceptance. The retained patch demonstrates those technical choices without changing the effective package.

No psyche decision is required. The unresolved full-suite failures are upstream test-fixture defects and ordinary implementation work, not authority, privacy, or value choices.
