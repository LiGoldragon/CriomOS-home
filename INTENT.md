# INTENT — CriomOS-home

CriomOS-home owns the user-side Home Manager profile ladder for the
operator desktop. Profile package selections express durable user
environment intent, while system capabilities, users, groups, devices,
and services remain in CriomOS.

## Desktop survivability

- The Niri desktop exposes a dedicated rescue terminal through a custom
  keybinding. The rescue terminal is separate from ordinary terminal
  windows so it can receive protected interactive-resource policy without
  also boosting heavy agent or build children.
- Desktop resource protection must not make Home Manager own or reconcile
  live graphical-session slices such as `session.slice`. Protect specific
  recovery components and future workload scopes without risking logout of
  the active compositor session.
- UI-priority policy is component-specific and runtime-applied: Niri, the
  user D-Bus bus, desktop portals, PipeWire/WirePlumber, Noctalia/QuickShell,
  Mako, and the dedicated rescue terminal receive protection through their
  own units/scopes rather than through broad parent-slice ownership.

## Shell safety

- The base Home profile provides reusable Nix store path redaction helpers
  so agents and users can filter human-facing build, evaluation, and deploy
  logs without rewriting ad-hoc shell redactors.

## Medium profile

- The medium Home profile includes Linux webcam control tooling so Bird's
  normal Zeus desktop environment can configure USB webcam focus and
  related camera controls without mutable, out-of-profile installs. The
  current package for this role is `cameractrls`.
- Ordinary video production tools belong in the regular medium Home
  profile: capture/edit/inspect/caption/TTS utilities and caption fonts
  should be present without mutable installs. Heavy speech-to-text or
  model-cache stacks stay out of the normal medium profile until their
  AI-node or larger-profile shape is settled.

## Dictation

- Dictation device stability is push-oriented: Home should use declarative
  PipeWire/WirePlumber policy and stable service bindings rather than polling
  loops that repeatedly inspect or repair the audio graph after the fact.
- Dictation microphone support should stay small and subtractive: for the DJI
  and Whisrs path, prefer reducing or deleting brittle PipeWire/WirePlumber
  special handling over adding more keepalive code. The psyche said, *I don't
  want this to blow up into a huge pile of code. So let's try to reduce the
  amount of code instead of keeping on adding.*
- Speech-to-text should prefer the connected DJI Bluetooth microphone when its
  raw PipeWire source is present, while retaining ordinary laptop-microphone
  fallback and avoiding a hard virtual hot-loop dependency.

## Spirit deployment

- CriomOS-home builds Spirit's binary daemon startup archive during Nix
  build/evaluation so the user service starts from a ready rkyv
  configuration archive. Service startup does not generate the archive.
