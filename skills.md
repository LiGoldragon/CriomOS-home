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
- The canonical user-profile Rust toolchain:
  `packages/rust-toolchain/default.nix`.

This repo does not own:

- NixOS users, groups, udev, kernel modules, or `/dev/uinput`.
- Horizon schema or method computation.
- Emacs internals.
- Per-repo Rust build toolchains. Rust application repos may pin their
  own compiler for builds; the Home toolchain is for interactive agent
  work such as `cargo fmt`, `cargo clippy`, and editor integration.

Node names are not feature predicates in Home Manager either. Use them
only as rendered identity/display data. If a module needs to know whether
there is an AI provider, tailnet controller, or other cluster role, read
the projected Horizon role data or extend horizon-rs.

## Rust Toolchain

Use `packages.rust-toolchain` as the canonical profile Rust toolchain.
It comes from `inputs.rust-overlay` and is pinned by
`CriomOS-home/flake.lock`; do not install bare `pkgs.cargo`,
`pkgs.rustc`, or `pkgs.rustfmt` into profiles.

The package uses the minimal Rust profile plus explicit components:
`rust-src`, `rust-analyzer`, `rustfmt`, and `clippy`. That keeps profile
weight low while ensuring agents can run `cargo fmt`, `cargo clippy`,
and language-server tooling everywhere.

## Browser Automation

The min profile installs `packages/playwright-cli` with browser downloads
disabled. It is the deterministic shell surface for agent browser
automation. The package also exposes `playwright-chrome`, which reads the
Chrome browser-extension token from
`gopass:chrome-browser/playwright-mcp-extension-token` and sets the Chrome
executable path for NixOS.

Browser-use is a separate delegated browser-agent layer: it may attach to
Chrome through CDP, but do not model it as a wrapper around the Playwright
CLI.

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
- `Mod+Ctrl+V` cancels the active recording. On the default batch
  backend this stops local capture, discards the audio, avoids the
  transcription request, and does not write Whisrs history.
- Transcript history is local application state at
  `~/.local/share/whisrs/history.jsonl`; the service wrapper creates it
  private.
- Noctalia shows the Whisrs recording state through the system tray item
  and the `whisrs-level` plugin. Status icons live in
  `packages/whisrs/`.
- DJI Mic keepalive keeps the microphone hot by holding a PipeWire stream
  open through a loopback sink. It may call BlueZ `Connect` before the device
  is connected, but after PipeWire exposes the Bluetooth card it must repair
  profile churn through PipeWire profile reassertion. Do not use BlueZ
  profile-specific connection calls as the steady-state repair loop; that
  hammers the wrong HSP/HFP side on this device and reintroduces the wake-delay
  failure.

Do not put API keys in Nix, system-wide environment, shell profiles, or
bar/widget scripts. If a change needs a paid STT call, ask first unless
the user explicitly authorized that call in the current task.

---

## Verification

### FullOS propagation

CriomOS-home is a flake input of CriomOS. A pushed CriomOS-home
commit is not part of a FullOS deployment until CriomOS's
`flake.lock` pins `inputs.criomos-home` to that commit. `nix
--refresh` on the CriomOS flake refreshes CriomOS itself; it
does not override nested input pins.

When a CriomOS-home change is intended to ship through FullOS,
push the CriomOS-home commit, run `nix flake update criomos-home`
in CriomOS, and update any top-level CriomOS input that the home
flake follows and needs at runtime. Commit and push CriomOS's
`flake.lock`, then deploy FullOS through lojix. Treat the
downstream lock bump as part of the home change, not as a
separate optional cleanup.

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
