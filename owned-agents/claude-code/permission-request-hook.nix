{
  writeShellApplication,
  jq,
  coreutils,
}:
# Claude Code PermissionRequest hook.  Under bypassPermissions the only Bash
# request that still reaches a human is the binary's dangerous-removal safety
# check (`circuitBreaker: "dangerousRemoval"`), which no allow rule can answer.
# The living's ruling (2026-10-03, flow 28d847): deny it with a rewrite message
# so nothing waits, and record every request.  Outside bypass the hook only
# records and leaves the ordinary prompt in place.
writeShellApplication {
  name = "claude-permission-request-hook";
  runtimeInputs = [
    jq
    coreutils
  ];
  text = ''
    message="Destructive commands name literal paths, never shell variables; rewrite the path as a literal and run again."
    input="$(cat)"
    mode="$(jq -r '.permission_mode // ""' <<<"$input" 2>/dev/null || true)"
    tool="$(jq -r '.tool_name // ""' <<<"$input" 2>/dev/null || true)"
    if [ "$mode" = bypassPermissions ] && [ "$tool" = Bash ]; then
      decision=deny
    else
      decision=prompt
    fi

    # Recording never blocks the decision.
    {
      state_directory="''${XDG_STATE_HOME:-$HOME/.local/state}/claude"
      mkdir -p "$state_directory"
      jq -c --arg time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg decision "$decision" \
        '{time: $time, session: .session_id, decision: $decision, mode: .permission_mode, tool: .tool_name, cwd: .cwd, command: .tool_input.command}' \
        <<<"$input" >>"$state_directory/permission-requests.jsonl"
    } 2>/dev/null || true

    if [ "$decision" = deny ]; then
      jq -cn --arg message "$message" \
        '{hookSpecificOutput: {hookEventName: "PermissionRequest", decision: {behavior: "deny", message: $message}}}'
    fi
  '';
}
