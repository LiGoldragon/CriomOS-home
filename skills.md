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

## Google Workspace CLI

The min profile installs the no-MCP `gws` Google Workspace CLI through
`packages/gws`. The wrapper reads OAuth client identity from `gopass`
when the entries exist:

- `google-workspace/gws/client-id`
- `google-workspace/gws/client-secret`

`gws` owns its OAuth refresh credentials and token cache through its
native encrypted config under `${XDG_CONFIG_HOME:-$HOME/.config}/gws`.
Do not move those token files into Nix, Home Manager text, reports, or
public commits. If the credential storage shape changes, keep secret
bytes in `gopass` or the tool's encrypted runtime store, never in the
Nix store.

The local Pi package `pi-criomos` carries a `gws` skill so agents load
the no-MCP command rules before using Google account data. Google
Workspace account contents are private personal-affairs material:
assistant/counselor reports go to private report repositories, and
public repo files carry only mechanism and non-sensitive status.

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
- Listener is installed for a production trial beside Whisrs. `Mod+Alt+L`
  runs the Nix-managed `listener-toggle-capture` wrapper; Whisrs keeps
  `Mod+V`, `Mod+Shift+V`, `Mod+Alt+V`, and `Mod+Ctrl+V`.
- `listener.service` starts `listener-daemon` with default-source capture
  and clipboard delivery. Real STT is configured only by
  `~/.config/listener/environment` setting `LISTENER_TRANSCRIPTION_PROGRAM`;
  without that variable Listener returns its explicit not-configured
  transcript.
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

## Desktop survivability safety

Do not manage `session.slice` or other live graphical-session container slices
through Home Manager activation. Niri and core session services run beneath
`session.slice`; reconciling that unit during a live `UserEnvironment`
activation can terminate the compositor and log the user out. Prefer protected
transient scopes for specific recovery tools, and design broader resource policy
through a path that cannot stop the active session.

The `ui-priority.nix` module follows that rule. It installs
`criomos-ui-priority-apply`, `criomos-ui-priority-status`, and the oneshot
`criomos-ui-priority.service`. The apply command uses
`systemctl --user set-property --runtime` on specific UI services and transient
app scopes; it must not write persistent drop-ins for `session.slice` or restart
the compositor.

## Nix output redaction helpers

The base Home profile installs `redact-nix-store-paths`, a pipe filter that
replaces concrete `/nix/store/<hash>-...` paths with `/nix/store/<redacted>`.
Interactive zsh shells also define `with-nix-store-redaction`, which runs a
command with both stdout and stderr filtered through that command.

Use these helpers for human-facing build/evaluation/deploy logs instead of
rewriting ad-hoc `sed` redactors in every shell command. Keep store paths in
shell variables when the path itself is load-bearing.

## Verification

### CompleteHost propagation

CriomOS-home is a flake input of CriomOS. A pushed CriomOS-home
commit is not part of a `CompleteHost` deployment until CriomOS's
`flake.lock` pins `inputs.criomos-home` to that commit. `nix
--refresh` on the CriomOS flake refreshes CriomOS itself; it
does not override nested input pins.

When a CriomOS-home change is intended to ship through `CompleteHost`,
push the CriomOS-home commit, run `nix flake update criomos-home`
in CriomOS, and update any top-level CriomOS input that the home
flake follows and needs at runtime. Commit and push CriomOS's
`flake.lock`, then deploy `CompleteHost` through Lojix. Treat the
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

Submit deployment work directly through the typed Lojix interfaces. Use
`meta-lojix` for privileged deploy admission and `lojix` for observations;
there is no profile wrapper or compatibility translator. A user-environment
activation is submitted as a `UserEnvironment` deploy through the selected
CriomOS flake revision, with an explicit builder value (`None` or
`(Some <builder-node>)`) and explicit substituter records when needed. The
accepted admission shape is `DeployAccepted DeployHandle`; it proves only that
the daemon accepted the request. Use `lojix` typed generation/status/event
queries for terminal evidence and filter human-facing logs through
`redact-nix-store-paths` or `with-nix-store-redaction`.

For Niri settings, repo changes and builds are not live runtime state. After a
`UserEnvironment` activation reaches the expected profile state, the operator
may ask the running compositor to load the activated config with
`niri msg action load-config-file`. This IPC reload is an explicit operator
procedure, not a deploy-tool side effect, and it is not a process signal; SIGHUP
remains forbidden. Only test window rules, keybindings, or other Niri runtime
settings after both activation and reload have happened.

---

## See also

- CriomOS's `skills.md` for system-side boundaries.
- primary's `skills/stt-interpreter.md` for reading dictated prompts.
- primary's `skills/skill-editor.md` for editing this file.
- lore's `programming/push-not-pull.md` for status/indicator design.
