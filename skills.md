# Skill — CriomOS-home

*Working effectively in the user-side Home Manager profile.*

---

## What this skill is for

Use this when changing the operator's home profile, desktop session,
Niri bindings, Noctalia status bar, user-scoped packages, or dictation
tooling.

CriomOS-home owns per-user configuration. It is consumed by CriomOS for
full system deploys and can also be activated as a home-only profile
through lojix. System privileges, groups, kernel modules, and device
rules belong in CriomOS.

---

## Start here

Read `AGENTS.md`, lore's `AGENTS.md`, CriomOS's `AGENTS.md`,
`ARCHITECTURE.md`, and `docs/ROADMAP.md` before editing. If working from
the primary workspace, also follow its `skills/autonomous-agent.md` and
claim the repo with the operator lock.

Use `bd list --status open` first. Reports are point-in-time records;
the current implementation lives in the modules and packages.

---

## Boundaries

This repo owns:

- `modules/home/` Home Manager modules and profile ladder.
- `packages/` user-scoped packages and patched upstream tools.
- Niri keybindings and Noctalia user configuration.
- User services such as `whisrs.service`.

This repo does not own:

- NixOS users, groups, udev, kernel modules, or `/dev/uinput`.
- Horizon schema or method computation.
- Emacs internals.

Node names are not feature predicates in Home Manager either. Use them
only as rendered identity/display data. If a module needs to know whether
there is an AI provider, tailnet controller, or other cluster role, read
the projected Horizon role data or extend horizon-rs.

---

## Dictation

The daily STT path is Whisrs. The owning files are
`modules/home/profiles/min/dictation.nix`,
`modules/home/profiles/min/sfwbar.nix`, and `packages/whisrs/`.

Important current shape:

- Whisrs is built from `inputs.whisrs-src` with crane. The input is
  the `LiGoldragon/whisrs` `criomos` branch, which carries the
  CriomOS dictation safety, recovery, status-bar, and transcript
  recall changes.
- `packages/whisrs/` owns packaging, wrappers, and status icons. Rust
  code changes live in the Whisrs fork, not in a local patch stack.
- Only the daemon wrapper reads `gopass openai/api-key` into
  `WHISRS_OPENAI_API_KEY`.
- The Whisrs fork clears vendor key environment variables after backend
  construction so helper commands do not inherit them.
- `Mod+V` is clipboard-only dictation. This is the safe default because
  it does not inject transcript letters through the compositor seat.
- `Mod+Shift+V` toggles direct dictation, copies the full transcript to
  the clipboard before keyboard insertion, and writes Whisrs history.
  Treat it as the dangerous path for targets where direct key injection
  is explicitly worth the risk.
- `Mod+Alt+V` opens `whisrs-recall`, a Fuzzel-backed selector over
  recent Whisrs history. The selected full transcript is copied to the
  clipboard; it does not inject text into the focused window.
- Transcript history is local application state at
  `~/.local/share/whisrs/history.jsonl`; the service wrapper creates it
  private.
- Noctalia shows the Whisrs recording state through the system tray item
  and the `whisrs-level` plugin. Status icons live in
  `packages/whisrs/`.

Do not put API keys in Nix, system-wide environment, shell profiles, or
bar/widget scripts. If a change needs a paid STT call, ask first unless
the user explicitly authorized that call in the current task.

---

## Verification

For local checks that do not call paid APIs:

- `systemctl --user is-active whisrs.service`
- `whisrs status`
- `whisrs log -n 1`
- D-Bus tray metadata via the StatusNotifierItem bus item
- `whisrs toggle` followed by `whisrs cancel` only when checking
  recording state without transcription

Build from pushed origin with `--refresh` before treating package changes
as verified. Home activation should restart `whisrs.service`; do not
signal niri.

For Niri settings, repo changes and builds are not live runtime state. After
pushing, run lojix `HomeOnly ... Activate`, then ask the running compositor to
load the activated config with `niri msg action load-config-file`. This IPC
reload is not a process signal; SIGHUP remains forbidden. Only test window
rules, keybindings, or other Niri runtime settings after both activation and
reload have happened.

---

## See also

- CriomOS's `skills.md` for system-side boundaries.
- primary's `skills/stt-interpreter.md` for reading dictated prompts.
- primary's `skills/skill-editor.md` for editing this file.
- lore's `programming/push-not-pull.md` for status/indicator design.
