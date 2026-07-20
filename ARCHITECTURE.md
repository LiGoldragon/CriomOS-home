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
  The cluster Rust toolchain is the newest nightly, pinned durably through
  fenix's flake lock — bumping fenix advances Rust cluster-wide — rather
  than a rolling stable channel guarded by per-crate frozen sha256.
  Per-crate flakes route their toolchain through a shared `rust-build`
  whose `fromToolchainFile` yields the fenix complete nightly (all
  components, no hash); a crate gets nightly by repinning `rust-build`.

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

Core interactive programs — the desktop shell/compositor, terminal
emulator, launcher, and the dedicated rescue terminal — should keep higher
effective CPU/IO/memory priority than bulk work so the operator stays in
control under resource pressure; the Linux mechanism for this is surveyed
rather than assumed. The rescue terminal is deliberately separate so it
receives protected policy without boosting heavy agent or build children.

For desktop and resource-safety work, the discipline is research-first:
study the necessary components and mechanisms, then implement the smallest
safe shape that preserves the active session — no shortcut implementations.

### Activation safety

A Home-profile activation persists across reboot — a reboot that restores
an older deployed Claude version is a bug to investigate — and it keeps the
active graphical session and user logged in while preserving active agent
sessions. Live Home/Niri/desktop deploys with ongoing agents proceed only
when the operator confirms the disruption window. Pi operator-safety, by
contrast, proceeds without asking merely because a repository is dirty.

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
Listener path, prefer reducing or deleting brittle PipeWire/WirePlumber special
handling over adding more keepalive code. Desktop audio prefers the connected
DJI Bluetooth microphone through system default-source policy when its raw
PipeWire source is present, while retaining ordinary laptop-microphone
fallback and avoiding a hard virtual hot-loop dependency or dictation-specific
source wrapper. A DJI keep-alive may exist as a sidecar consumer of the real
DJI source: it keeps that specific mic awake, but the system and Listener still
select the real microphone source rather than the keep-alive interface. The
DJI keepalive keeps the microphone hot for speech-to-text so recording does
not lose the first two or three seconds to Bluetooth wake/profile churn.

### Recording-system data flow

The recording-system flow runs from the operator's laptop microphone,
across the network, to the large-AI node where the always-on capture buffer
and real-time multi-modal inference live. The laptop is the audio origin;
the large-AI node is the processing host. The laptop-to-large-AI-node hop is
explicit: audio source and processor are distinct machines, not assumed to
be the same host.

### Spirit deployment

CriomOS-home builds Spirit's binary daemon startup archive during Nix
build/evaluation so the user service starts from a ready rkyv configuration
archive. Service startup does not generate the archive.

### Emacs native compilation

For nix-managed Emacs configs, `.eln` native-compiled artefacts are
produced at Nix build time as part of the derivation. Runtime JIT
native-compilation is forbidden: it invalidates on every Nix rebuild.
(Emacs *internals* remain owned by CriomOS-emacs; this is the build-time
artefact policy for the home-managed config.)

## Agent and browser tooling

Coding-agent harnesses and their extensions are packaged declaratively
through Nix, with Nix paths hidden from internal views. Pi extension sources
go in flake inputs with hashes in `flake.lock`; persona-Pi packages standard
Pi extensions through Nix (the extension packaging discipline lives in
[`docs/pi-extensions.md`](docs/pi-extensions.md)). The bundled
`pi-subagents` extra subagents are a review source mined selectively for
useful material — adopted deliberately, case by case, rather than imported
wholesale. Persona Pi agent-chain automation in the user profile runs
without a manual UI approval for already-authorized work, so the agent can
start automated work without the operator in the loop.

Agent Intercom is installed as one pinned protocol-v3 family: Pi is the
primary manager with its native adapter and orchestrator, while Codex, Claude
Code, and OpenCode receive their supported adapters. The user profile owns
broker state, adapters, user services, MCP registration, OpenCode plugin
configuration, and remote-manager credential references. Cross-machine access
uses only the upstream authenticated `remote-gateway.sock` through supported
SSH reverse Unix-socket transport; it never forwards `broker.sock` and never
puts enrollment, reconnect, OAuth, pairing, or private-key material in a
profile derivation.

The user profile also owns the maintained unofficial Linux Codex Desktop
module. It pins `CODEX_CLI_PATH` through the module launcher, enables its
supported Linux Computer Use integration without weakening Electron sandboxing,
and enables experimental Remote Mobile Control through its declarative user
service. Linux remote hosting remains experimental and account rollout or
pairing remains an interactive OpenAI-controlled operation.

A Nix utility fetches Hugging Face models by URL or query, mirroring
`nix-prefetch-url`: it prefetches via the Hugging Face CLI, hashes, and
writes a fetcher derivation parameterised by the HF URL/query — a workspace
tool for getting any HF model into the store. Video-editing agents get most
normal video-editing tools through the regular medium profile, with
exceptions only for unusually large dependencies.

Browser control is three-tier: a cloud orchestrator (any agent) instructs a
local actor model (e.g. Gemma) on the CriomOS AI node, which reads the
browser visually via the Chrome DevTools Protocol and acts; the CLI's model
calls go to that local node, not an external API. CriomOS-home packages
`browser-use` with a wrapper using the local Gemma model served by the
large-AI node when present. The CLI runs from outside the cloud daemon as a
packaged PATH command (no orchestrator triad or RemoteBrowse op); a
Playwright MCP path is optional. Supervised scout mode — scan, report state
and next steps, await human decision before consequential actions — is used
on the operator's main Chrome profile where safe.

## Update synchronization

Claude Code, Codex, and Pi are updated together through CriomOS-home and the
full CriomOS lock, so active profiles and full-system deployments stay in
sync after crashes or reboots.

Cluster-host update authority: Bird/Zeus update authority uses LiGoldragon
`main` by default, not per-user branches. For Crayon OS host maintenance the
maintainer has root SSH on all cluster hosts but cannot SSH as Bird on Zeus.
Bird's Zeus home-profile redeploy therefore runs through lojix's root-mediated
user-environment activation: lojix reaches Zeus as `root` and drops privilege to
Bird through a login (`runuser --login`) to set and activate Bird's Home Manager
profile, needing no direct Bird SSH. Witnessed working as of lojix `0.4.5`.

## Networking and media

Mobile Android clients on the Criome WiFi access point should get
near-native name resolution for cluster services; the AP-to-Android
resolving path is improved before falling back to ordinary public DNS names.

Syncthing is excluded from the phone media-mirror path because it is too
heavy for the phone; Immich remains the phone uploader/gallery candidate,
and any raw-file surface must avoid adding Syncthing to Android.

## Secrets scoping

Secret paths are scoped to the resource they serve. Local-service tokens are
scoped to the zone where the service lives, distinct from provider-scoped
paths that are global to a provider; a zone-scoped local-LLM API token
survives the large-AI role moving between hosts because it is zone-scoped,
not host-scoped. The Playwright Chrome browser-extension token lives in
gopass; browser-automation wrappers read that entry at runtime without
printing the token.

## Firmware gating

Firmware gating reuses existing policy surfaces rather than adding broad
Horizon schema.

## Status

CANON. Active.

## Cross-cutting context

- Project-wide architecture: criome's `ARCHITECTURE.md`.
