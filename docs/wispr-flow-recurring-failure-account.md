# Wispr Flow recurring failure account — 2026-10-29

## Status

Wispr Flow is running on `ouranos`. The recovery launch has two systemd scopes belonging to one process tree: `app-wispr-flow-restart-3fa658.scope` holds the FHS `bwrap` parent and `app-wispr-flow-1765973.scope` holds its Electron child, renderers and helper. A passive status-socket read at the end of this investigation reported `recording`, `hands_free=true`; that is evidence the process and bridge were live, not a lasting functional witness. The living reported one successful transcription after the earlier recovery and then another failure. The recurring bug remains open.

## Recovery performed

Before mutation, the old transient scope was active, the status/control sockets existed, and the technical launcher log ended in a processing timeout and terminal Error. I stopped only that exact scope, witnessed the Wispr process and sockets disappear, then launched the deployed executable with:

```sh
systemd-run --user --scope --unit=app-wispr-flow-restart-3fa658.scope \
  /home/li/.nix-profile/bin/wispr-flow
```

The new scope entered active/running at `2026-10-29 17:38:07 CST`; its root PID was `1765973`, invocation ID `a4411f08b9e24c83811562ae3bad2507`, and both sockets were recreated at 17:38:08. I did not inspect dictation content or capture microphone data. This was recovery, not a root-cause fix.

## Latest witnessed failure sequence

The filtered technical state transitions in `~/.cache/wispr-flow/launcher.log` showed:

1. 17:29:16 listening -> processing -> idle at 17:29:17.
2. A later pipeline returned the visible state to Idle at 17:36:20.218 but was still doing tail work.
3. A new dictation started at 17:36:24.068 and entered Processing at 17:36:26.826.
4. Its recording-done callback was rejected at 17:36:26.827 as "already processing".
5. The preceding pipeline did slow History work and reached its final reset guard at 17:36:37.701, where it detected the new dictation and preserved its state.
6. No recording-done retry occurred. Processing timed out at 17:36:50.825 and entered Error; at 17:36:50.827 the launcher reported that `activeDictationSession` was still set.

This directly establishes a dropped-completion race followed by the terminal-error cleanup defect. It does not identify why the preceding pipeline took long enough to overlap the next dictation.

## Causal recording-done race

The deployed archive is `/nix/store/drrrcy4vbli1yyw2ikfcf5xhm6cbrsq5-wispr-flow-1.6.774+criomos.11/lib/wispr-flow/electron/resources/app.asar`. Its minified main bundle's module `63205`, around byte 3,965,874, declares one process-wide Boolean latch, `Lt`, around `onRecordingDone`. The handler first accepts a callback when it is testing, has no transcription UUID, or its UUID equals the current global UUID. It then rejects every accepted callback while `Lt` is true. It sets `Lt` before processing and clears it only in the outermost `finally`, around byte 3,983,690, after the rest of the pipeline and its inner cleanup.

The inner cleanup explicitly notices when a new global UUID has begun and skips resetting that new dictation. Thus the application permits a new dictation while the preceding pipeline finishes, but the process-wide latch still rejects the new dictation's completion. That callback returns without processing its recording, and the observed run produced no later retry.

The same signature appears five times in the technical launcher metadata:

| Duplicate callback line and time | Following timeout line and time | Gap |
| --- | --- | --- |
| 761066, 18:32:37.115 | 761192, 18:33:01.112 | 24 s |
| 847987, 06:12:59.223 | 848121, 06:13:23.220 | 24 s |
| 897309, 16:57:21.527 | 897364, 16:57:45.526 | 24 s |
| 900531, 17:15:28.165 | 900610, 17:16:18.689 | 50 s |
| 902814, 17:36:26.827 | 902939, 17:36:50.825 | 24 s |

The repeated duplicate-to-timeout chain and the handler's return path establish the shared race. The source of the preceding pipeline's latency remains unknown: slow SQL and I/O are present in some affected windows, but the evidence does not identify one shared latency cause.

A per-transcription UUID latch is directionally relevant because it can distinguish a genuine same-session duplicate from a new session. A direct Boolean-to-UUID-set replacement is unsafe, however. The handler reads and mutates the shared global `c.ZZ` audio packets, status, timing, application context, current task and UUID throughout; allowing two UUID pipelines to run concurrently can mix their state. The handler also deliberately admits callbacks with a missing UUID and callbacks in Testing, whose identity semantics a keyed latch would have to define. Every return and exception path would have to release the correct key.

Whether the pipeline should serialize completions or isolate every per-transcription value is a design decision pending Claude review and a proposal to the living. This account selects neither and implements neither.

## Historical evidence

- System coredump metadata records Wispr SIGTRAP on 2026-09-13 and SIGABRT on 2026-10-03, twice on 2026-10-07, and on 2026-10-15. These are dead-process failures that supervision can recover from; their individual causes were not established here.
- The 2026-10-28 kernel OOM record listed Wispr processes but killed a Python process, not Wispr. It is not evidence that swap or the machine jam caused the latest Error.
- Earlier beads `primary-vx3` and `primary-aje` landed the Linux status/control bridge, truthful state and meter behavior. They did not add lifecycle supervision or repair processing-timeout cleanup.
- `primary-swaf.1` remains the current recurring-bug child. The queried bead record names no earlier completed repair of this recurrence.

## Implementation map

### Packaging and launch

- `wispr-flow-linux/nix/wispr-flow.nix:19-36` pins version `1.6.774+criomos.11` and the immutable official Windows installer.
- `nix/wispr-flow.nix:107-198` extracts the Electron app, applies the fail-closed Linux patch suite, installs the status bridge/client, replaces Windows native modules, repacks the archive, verifies markers, and stages the pinned Linux helper.
- `nix/wispr-flow.nix:279-352` declares uinput/input access and installs the launcher and status client.
- `nix/fhs.nix:24-35` wraps the package in an FHS environment with glibc and Wayland/X11 clipboard tools.
- `nix/runtime-inputs.nix` pins architecture-specific helpers and native modules.

### Input, audio and state

- `scripts/patches/helper-resolver.sh` selects the bundled Linux helper.
- `scripts/patches/helper-env.sh` preserves the graphical/session environment needed for Wayland/X11 injection and clipboard backends; without it capture can work while text injection is inert.
- `scripts/patches/linux-status-meter-worklet.sh` and `linux-status-meter-renderer.sh` project capture/meter state without exposing audio content.
- `scripts/patches/linux-status-bridge.sh:61-85` hooks the app's authoritative state setter, publishes typed state, and registers the hands-free control action.
- `scripts/wispr-status-bridge.cjs:36-52` owns the status/control sockets, serializes requests, waits for a state publication and returns typed errors.
- `scripts/wispr-flow-status.cjs` is a mutating toggle client only; passive observation reads `wispr-flow-status-v2.sock` directly.

### Declarative ownership

`CriomOS-home/modules/home/profiles/min/wispr-flow.nix` evaluates the `wispr-flow-linux` package for Medium-and-larger Home profiles. Before this work it installed the package but explicitly declared no Home service, autostart or keybinding.

## Codex lifecycle proposal

Branch `stt-codex` in `/home/li/worktrees/criomos-home-stt-codex`, commit `9a7871b1321b2daf548f0e56e22625f18da9bbba` (pushed), adds a graphical-session user service using the evaluated package, `Restart=on-failure`, and a two-second delay. The isolated `wispr-flow-profile-tier` check passed at `/nix/store/a6yvdn10prpmwg9g7q1llnnsl0mw94mz-wispr-flow-profile-tier`.

This proposal covers a process that exits abnormally and makes the graphical session the declarative owner. It does not recover a live process stuck in Error. It also does not, by itself, prevent a user or desktop launcher from starting a second unmanaged instance. Runtime restart semantics were not exercised.

## Audit of Claude commit `e56a9d0`

I audited `/home/li/worktrees/wispr-flow-linux-stt-claude` read-only against the deployed app archive and latest failure sequence.

The patch changes the Error-state toggle from `not_toggleable` to:

1. call the app's own `tryDismissDictation(UserActionEscape)`;
2. start hands-free through the existing Deeplink action;
3. return the requested hands-free state.

The actual deployed minified bundle independently establishes that `tryDismissDictation` is synchronous: it clears the active sentinel, changes the state to Dismissed, cancels an active dictation when needed, and clears timers before returning. The patch therefore orders cleanup before start; an async race I initially considered is disproved. The referenced export, enum and module anchors each occur exactly once.

Independent check:

```text
nix build --no-link --print-out-paths .#checks.x86_64-linux.status-bootstrap
/nix/store/c9ajk9092sf29wf8nv7v78w974lm57v7-wispr-flow-status-bootstrap
```

The check passed. It covers the successful Error dismissal/start path plus the existing Idle, Dismissed, locked Listening, Processing and unlocked Listening matrix. The bridge separately converts a rejected action to `action_failed`.

Gaps:

- no focused negative test asserts behavior when dismissal throws, start rejects, or Error is toggled repeatedly;
- the successful test mocks dismissal rather than asserting the real sentinel and final lifecycle state;
- the patch supplies explicit recovery from terminal Error but does not prevent the processing timeout;
- it does not autonomously recover Error or solve process ownership/duplicate launch.

The Claude Error recovery and Codex lifecycle proposal address different failure classes and can compose. `e56a9d0` can recover through the control surface after the race has reached Error, but it does not prevent the global latch from dropping the new recording-done callback. Neither is a complete recurring-root-cause fix.

## Current process ownership witness

The two active scopes are not two Wispr applications. `app-wispr-flow-restart-3fa658.scope` owns `bwrap` PID 1765963 and supporting zygote/crashpad processes. Its child Electron main PID 1765973 was placed in `app-wispr-flow-1765973.scope`, which owns the renderers and the only observed Linux helper, PID 1766176. Both have the same launch time and session, and PID 1765973 has PID 1765963 as its parent.

At the time of this read-only snapshot, the sole Electron main owned both expected listeners: `wispr-flow-status-v2.sock` on file descriptor 74 and `wispr-flow-control-v2.sock` on file descriptor 77. This current snapshot rules out a current duplicate main, helper or socket owner. It does not establish the device, helper or socket state at an earlier failure.

## Ctrl+Enter correction related to this recovery session

The effective Ghostty 1.3.1 default bound `ctrl+enter=toggle_fullscreen`. Niri's complete binding section had no plain Ctrl+Enter. The supported Linux config path is `$XDG_CONFIG_HOME/ghostty/config.ghostty`; the older `ghostty/config` is ignored by this version.

Live file `/home/li/.config/ghostty/config.ghostty` received `keybind = ctrl+enter=unbind`, validated successfully, and Ghostty reloaded it with its documented SIGUSR2 mechanism while retaining the same PID. `ghostty +show-config` then showed no Ctrl+Enter binding. Declarative branch `keyboard-ctrl-enter-3fa658`, pushed commit `b19f03a4cf1d640bdaee70d81918d218596af9a1`, adds the unbind to both generated Chroma configs. The source branch still needs normal merge/deployment; until then a Chroma rewrite can replace the live correction. Closure awaits the living's Claude TUI push-send witness.

## Conclusions and unknowns

Observed causes are separated:

- A process-wide recording-done latch dropped the completion callback for a new dictation while the preceding pipeline was still finishing. Five observed instances were followed by processing timeout.
- The latest functional failure ended in a live Error with a stale active-session sentinel after a processing timeout.
- Historical crashes leave no process and need lifecycle supervision.
- The absence of one declarative owner permits manual/transient launch ambiguity.

Unknowns remain:

- why the preceding pipeline was slow enough to overlap the next dictation;
- the causes of the historical SIGTRAP/SIGABRT events;
- whether the latency is upstream network/server work, local IPC/helper work, SQL/I/O or another internal stage;
- whether either source proposal remains fixed across repeated real dictations.

The next design decision is how to preserve per-transcription identity without allowing shared global state to race: serialization or full isolation. It follows Claude review and a proposal to the living. Separately, the reviewed Error cleanup patch and single-owner lifecycle supervision can be tested for their narrower recovery roles. The living's repeated-use witness is required before closing `primary-swaf.1`.
