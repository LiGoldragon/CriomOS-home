# OOM policy of the terminal scopes.
#
# Ghostty (`linux-cgroup`, single-instance) puts every surface's shell into
# its own transient `app-ghostty-surface-transient-<pid>.scope`. The user
# manager's `DefaultOOMPolicy` is `stop`: when the kernel OOM killer takes one
# process in such a scope, systemd stops the whole scope and every other
# process in it -- an agent harness running in that terminal dies with the
# test binary that overran (ouranos, 2026-09-05 04:08). `continue` leaves the
# rest of the scope running; the kernel's kill of the offender is the whole
# reaction.
#
# systemd applies a dash-prefix drop-in (`app-ghostty-.scope.d`) to every
# unit whose name starts with that prefix, transient scopes included. The
# Ghostty application scope (`app-niri-ghostty-<pid>.scope`) and the rest of
# the user session keep the default. New surfaces pick the policy up after a
# `systemctl --user daemon-reload`; a running scope keeps the property it was
# started with.
#
# The rescue terminal is its own scope (niri.nix) and carries the same policy
# as a property of its `systemd-run` invocation.
{ ... }:
{
  xdg.configFile."systemd/user/app-ghostty-.scope.d/oom-policy.conf".text = ''
    [Scope]
    OOMPolicy=continue
  '';
}
