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

## Shell safety

- The base Home profile provides reusable Nix store path redaction helpers
  so agents and users can filter human-facing build, evaluation, and deploy
  logs without rewriting ad-hoc shell redactors.

## Medium profile

- The medium Home profile includes Linux webcam control tooling so Bird's
  normal Zeus desktop environment can configure USB webcam focus and
  related camera controls without mutable, out-of-profile installs. The
  current package for this role is `cameractrls`.
