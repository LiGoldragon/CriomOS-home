# ARCHITECTURE — CriomOS-home

home-manager profile as a standalone flake and CriomOS module.
Imported by `github:LiGoldragon/CriomOS` for full system deploys and
evaluated directly for home-only deploys.

## Role

Per-user configuration for the operator. Provides shell, dot-
files, package selections, and integration with
`github:LiGoldragon/CriomOS-emacs`.

Detailed staging lives in [`docs/ROADMAP.md`](docs/ROADMAP.md).
Pi extension packaging lives in
[`docs/pi-extensions.md`](docs/pi-extensions.md).

## Boundaries

Owns:

- `modules/` — home-manager modules.
- `packages/` — user-scoped packages and configurations.
- `homeConfigurations` — direct Home Manager activation packages keyed
  by projected horizon users.
- The user-facing Rust toolchain installed into profiles. Its canonical
  package is `packages.rust-toolchain`, pinned by this flake's lockfile.

Does not own:

- System-level configuration — that's CriomOS.
- Emacs internals — that's CriomOS-emacs.
- Rust toolchains for building individual Rust application repos when
  they intentionally pin their own compiler through their own flakes.

Cluster-specific choices enter through projected Horizon data. Home
modules must not branch on concrete node names from a particular cluster;
they consume semantic roles and capabilities and may render node names
only as identities, URLs, labels, or diagnostics.

## Profile ladder direction

CriomOS-home owns the user-side Home Manager profile ladder for the
operator desktop. Profile package selections express durable user
environment intent; system capabilities, users, groups, devices, and
services remain in CriomOS.

### Desktop survivability

The Niri desktop exposes a dedicated rescue terminal through a custom
keybinding. The rescue terminal is separate from ordinary terminal windows
so it can receive protected interactive-resource policy without also
boosting heavy agent or build children. Desktop resource protection must
not make Home Manager own or reconcile live graphical-session slices such
as `session.slice`; specific recovery components and future workload scopes
are protected without risking logout of the active compositor session.
UI-priority policy is component-specific and runtime-applied: Niri, the
user D-Bus bus, desktop portals, PipeWire/WirePlumber, Noctalia/QuickShell,
Mako, and the dedicated rescue terminal receive protection through their own
units/scopes rather than through broad parent-slice ownership.

### Shell safety

The base Home profile provides reusable Nix store path redaction helpers so
agents and users can filter human-facing build, evaluation, and deploy logs
without rewriting ad-hoc shell redactors.

### Medium profile

The medium Home profile includes Linux webcam control tooling so the normal
Zeus desktop environment can configure USB webcam focus and related camera
controls without mutable, out-of-profile installs; the current package for
this role is `cameractrls`. Ordinary video production tools belong in the
regular medium Home profile: capture/edit/inspect/caption/TTS utilities and
caption fonts are present without mutable installs. Heavy speech-to-text or
model-cache stacks stay out of the normal medium profile until their AI-node
or larger-profile shape is settled. Persona Pi agent-chain automation in the
user profile runs without requiring a manual UI approval for already-
authorized work, so the agent can start automated work without the operator
in the loop.

### Dictation

Dictation device stability is push-oriented: Home uses declarative
PipeWire/WirePlumber policy and stable service bindings rather than polling
loops that repeatedly inspect or repair the audio graph after the fact.
Dictation microphone support stays small and subtractive: for the DJI and
Whisrs path, prefer reducing or deleting brittle PipeWire/WirePlumber special
handling over adding more keepalive code. Desktop audio prefers the connected
DJI Bluetooth microphone through system default-source policy when its raw
PipeWire source is present, while retaining ordinary laptop-microphone
fallback and avoiding a hard virtual hot-loop dependency or Whisrs-specific
source wrapper. A DJI keep-alive may exist as a sidecar consumer of the real
DJI source: it keeps that specific mic awake, but the system and Whisrs still
select the real microphone source rather than the keep-alive interface.

### Spirit deployment

CriomOS-home builds Spirit's binary daemon startup archive during Nix
build/evaluation so the user service starts from a ready rkyv configuration
archive. Service startup does not generate the archive.

## Status

CANON. Active.

## Cross-cutting context

- Project-wide architecture: criome's `ARCHITECTURE.md`.
