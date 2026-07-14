# Pi-subagents fork delta ledger

## Scope and state

This ledger reconciles the historical CriomOS-home package at `pi-subagents` 0.31.0 with upstream 0.34.0. It records evidence; it does not change the effective package version or activate a system.

The retained reconciliation witness is `reconciliation/0.31.0-to-0.34.0.patch`, SHA-256 `ce23d291df868b87e84e342e3a9a3909677bc97ec60e2ef5a3d00ae7a5979ec4`. `reconciliation/0.34.0.nix` builds that patch against immutable upstream source. Decisions below remain **provisional for an actual package update** because the upstream and reconciled full test suites both retain three upstream failures. Targeted delta tests, the Nix build, package-content checks, and Pi load check pass.

## Candidate and provenance

| Field | Immutable identity or source path |
|---|---|
| Canonical upstream | `https://github.com/nicobailon/pi-subagents` |
| Packaged base | npm 0.31.0, Git commit `e4f06282d0c95856b36b7ec2893f4fd294ebfefe`, registry integrity `sha512-ffzM8T4rXb1jmlSfrjD5l9xv3KS4vH069Cka14LCbDw8bJxuB/HRd3QnQfSB0z61+cZO9Aq8M1eq3FdKVvCSPg==` |
| Historical package snapshot | CriomOS-home commit `8a6c5b154f7df63b65c6027ba41ea7c6496d60db`, `packages/pi-subagents/default.nix` and its six sibling patch files |
| Historical lock identity | `flake.lock` node `pi-subagents-src`, NAR `sha256-EmDqAPVqJ6hxuA3Yj8SikM2kA/oI6D1QEe/gPvJbIVw=` |
| Update target | npm 0.34.0, Git commit `12a157d2a70b2f4cbc004c020c5f9213b6d8eea8`, registry integrity `sha512-JGgSYaieZ/2QtsW6BwSV1SX6zMz+YpV0JXUjSTtgphpk+z5OOJVJ4D/tWnCxIURXKcgsam+1vQkQgQ5fhrasFA==` |
| Target source hash | GitHub archive NAR `sha256-RN8f5cT/oRSkqwOAmvJ2uJsOmScYb0ijwixTd75iGHk=` |
| Reconciliation package expression | `packages/pi-subagents/reconciliation/0.34.0.nix` |
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

### Clarify is explicit opt-in

- **Rationale provenance:** CriomOS-home commit `1dd3f033b8b322c31609e1c56c4da4b99a62bc25`, `agent-chain-clarify-opt-in.patch`.
- **Local implementation:** `src/extension/schemas.ts` hunk `@@ -246,7 +246,7`; `src/runs/foreground/chain-execution.ts` hunk `@@ -504,7 +504,7`.
- **Upstream counterpart:** 0.34.0 already uses `clarify === true` in `chain-execution.ts`; its schema retains the older ambiguous wording.
- **Status:** `partially absorbed`.
- **Candidate action:** reimplement only the schema contract; drop the absorbed execution hunk.
- **Pristine witness:** code search for `const shouldClarify = clarify === true` exits 0; schema search for `Omitted or false runs directly` exits 1.
- **Reconciled witness:** both searches exit 0; targeted `chain-execution.test.ts` passes omitted-clarify and explicit-true cases.
- **Decision state:** provisional for package landing because the full upstream suite is red, although the delta witness passes.

### Compact parent skill

- **Rationale provenance:** CriomOS-home commits `23665920be8e76c9029a546d1841654d68e39e54` and `60ed02dfbbd34bddef417abc2c75e5270b652959`.
- **Local implementation:** whole-file replacement in `skills/pi-subagents/SKILL.md`, original hunk `@@ -10,846 +10,127`.
- **Upstream counterpart:** 0.34.0 expands the skill to 918 lines and does not preserve the compact local operating contract.
- **Status:** `still absent`.
- **Candidate action:** reimplement the compact skill against the target; retain upstream source documentation outside the runtime skill when an actual update is prepared.
- **Pristine witness:** line-count-plus-required-phrase command exits 1 with 918 lines.
- **Reconciled witness:** the same command exits 0 with 136 lines and finds `Subagents are independent Pi processes.` and the selected-child runtime rule.
- **Decision state:** provisional for package landing; content witnesses pass.

### Detached runner peer isolation

- **Rationale provenance:** CriomOS-home commit `6bf5e7ec700a00f33b19fe0c24d63e93f9ea61ce`.
- **Local implementation:** `src/shared/utils.ts` hunks removing the eager coding-agent import and optionalizing `resolveConfigDirName`.
- **Upstream counterpart:** 0.34.0 removes the eager peer import and adds package-root/package-json resolution in `resolveConfigDirNameFromPackageJson`.
- **Status:** `fully absorbed` and extended upstream.
- **Candidate action:** drop the local patch.
- **Pristine witness:** absence of `import * as piCodingAgent` plus presence of `resolveConfigDirNameFromPackageJson` exits 0; the upstream config-directory unit tests pass in the full run.
- **Reconciled witness:** unchanged source and the same witness exit 0.
- **Decision state:** supported drop, but no effective package change is made here.

### Bounded detached-runner stderr

- **Rationale provenance:** CriomOS-home commits `60528d041c0ad784ba069781c17035ba9cafc5bc` and `f3fcf3e89b9448a5b99236415fe04fc207ddecd6`; local patch comment states diagnostic output must not change async execution.
- **Local implementation:** `src/runs/background/async-execution.ts` helper hunk near old line 215 and spawn wiring near old line 238.
- **Upstream counterpart:** 0.34.0 captures `runner.stderr.log` and reads a bounded tail during stale-run repair, but does not bound the on-disk log.
- **Status:** `partially absorbed`.
- **Candidate action:** retain only a target-native 64 KiB on-disk bound and its unit test.
- **Pristine witness:** stderr capture search exits 0; truncation-marker search exits 1.
- **Reconciled witness:** both searches exit 0; `bounds detached runner stderr while retaining the tail` passes and proves size at most 64 KiB, marker presence, and tail retention.
- **Decision state:** provisional for package landing; targeted behavior passes.

### Full child extension bridge

- **Rationale provenance:** CriomOS-home commit `bff854e76bf17457a201f643622ae3dc0334e2fe`; its harness witness required the configured child extension, bridge metadata, and absence of `--no-extensions`.
- **Local implementation:** `src/intercom/intercom-bridge.ts` hunks near old lines 238 and 365; `src/runs/shared/pi-args.ts` hunk near old line 125.
- **Upstream counterpart:** 0.34.0 removes the intercom sandbox gate and provides the native supervisor channel, fully absorbing both intercom hunks. It still emits `--no-extensions` when an explicit child extension list exists.
- **Status:** `partially absorbed`.
- **Candidate action:** drop the absorbed intercom hunks; reimplement only package-extension inheritance in `pi-args.ts`.
- **Pristine witness:** absence-of-`args.push("--no-extensions")` command exits 1.
- **Reconciled witness:** the command exits 0; the two target-native `pi-args` tests pass and prove configured, subagent-only, and fanout extensions remain explicit without disabling package inheritance.
- **Decision state:** provisional for package landing; target-native unit and Pi load witnesses pass.

### Empty evidence for read-only acceptance

- **Rationale provenance:** CriomOS-home commit `df85cb32f687bb4dde1401d5cdfc6e75076c01f2` and its added read-only acceptance tests.
- **Local implementation:** `src/runs/shared/acceptance.ts` hunk near old line 631 and new `test/unit/acceptance-read-only-evidence.test.ts`.
- **Upstream counterpart:** 0.34.0 requires non-empty changed-file and test arrays for every run.
- **Status:** `still absent`.
- **Candidate action:** reimplement rather than replay the old patch unchanged. The cleanly applicable old hunk allowed empty arrays for write-capable work and made upstream `checked mode rejects missing required evidence` fail. The retained target-native implementation gates empty arrays on a read-only inference reason and adds a negative writer test.
- **Pristine witness:** `allowEmptyChangeEvidence` plus the read-only test file check exits 1.
- **Reconciled witness:** the check exits 0; three dedicated tests prove explicit empty read-only arrays pass, missing fields fail, and explicit empty writer arrays fail.
- **Decision state:** provisional for package landing; the old implementation is rejected and the target-native tests pass.

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
| bounded stderr | 1 | 0 |
| full child package-extension inheritance | 1 | 0 |
| read-only empty evidence | 1 | 0 |

The focused Node command ran acceptance, async execution, Pi argument, and chain execution tests: 108 tests, 108 passed, 0 failed.

### Upstream and reconciled test suites

After `npm ci`, `npm run test:all` was run independently on both trees.

- Pristine upstream: 981 tests; 978 passed; 3 failed.
- Reconciled: 985 tests; 982 passed; 3 failed.
- The same three upstream tests fail in both trees: `sets the child intercom session name from env during agent startup`, `rewrites the final child-visible prompt through before_agent_start`, and `uses the fanout boundary through before_agent_start`. Each fails because the test double lacks `pi.registerTool` when `registerNativeSupervisorClient` runs.
- No new reconciliation-specific full-suite failure remains. The full-suite gate is still red, so this ledger does not call the package update complete.

### Nix package and contents

The retained witness was built with:

```sh
nix build --impure --no-link --print-out-paths --print-build-logs --expr \
  'let flake = builtins.getFlake "path:'"$PWD"'"; pkgs = flake.inputs.nixpkgs.legacyPackages.x86_64-linux; in pkgs.callPackage ./packages/pi-subagents/reconciliation/0.34.0.nix {}'
```

The fixed npm dependency identity is `sha256-IJJ3hceNvHUr5QFIa/+0tnxNiEPh7jifE9dvPHrLE58=`. The build passed. Package-content checks passed for package name/version/extension metadata, runtime dependencies, the compact skill, explicit-clarify logic, bounded stderr, child extension inheritance, and read-only acceptance gating.

### Pi extension load

A representative Pi package directory was supplied through `PI_PACKAGE_DIR`. The built Pi CLI loaded the Nix-built reconciliation candidate in RPC mode:

```sh
printf '{"type":"get_commands"}\n' | \
  PI_PACKAGE_DIR="$PI/lib/pi-monorepo/packages/coding-agent" \
  "$PI/bin/pi" --mode rpc --no-session --no-context-files --no-skills \
  -e "$CANDIDATE/share/pi-packages/pi-subagents/src/extension/index.ts"
```

The command exited 0, stderr contained no `Failed to load extension`, and Pi returned `{"type":"response","command":"get_commands","success":true,"data":{"commands":[]}}`.

## Result

This is a mixed reconciliation across six deltas: one upstream-owned delta supports dropping its patch; the four originally identified remainder-analysis deltas require target-native remainder work; and the cleanly applicable acceptance patch separately requires target-native reimplementation because its old implementation regresses write-capable acceptance. The retained patch demonstrates those technical choices without changing the effective package.

No psyche decision is required. The unresolved full-suite failures are upstream test-fixture defects and ordinary implementation work, not authority, privacy, or value choices.
