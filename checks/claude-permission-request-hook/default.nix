{ inputs, pkgs, ... }:
# The Claude settings merge declares the PermissionRequest hook beside
# bypassPermissions, keeps foreign hooks, and the hook denies a bypass Bash
# request with the rewrite message while recording every request.
let
  system = pkgs.stdenv.hostPlatform.system;
  user = {
    name = "hook-user";
    size = "Min";
  };
  horizon = {
    node = {
      behavesAs.edge = false;
      services = [ ];
      criomeDomainName = "hook.invalid";
    };
    exNodes = { };
    users = [ user ];
  };
  ownedAgentPackages = import ../../lib/owned-agent-packages.nix { inherit inputs pkgs; };
  configuration =
    (inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit
          inputs
          horizon
          user
          ownedAgentPackages
          ;
        hexis = inputs.hexis.packages.${system}.default;
      };
      modules = [
        (_: { _module.args.ownedAgentPackages = ownedAgentPackages; })
        ../../modules/home/core-packages.nix
        ../../modules/home/profiles/min/codex-remote-control.nix
        {
          home.username = user.name;
          home.homeDirectory = "/home/${user.name}";
          home.stateVersion = "26.05";
        }
      ];
    }).config;
  mergeSettings = configuration.home.activation.mergeClaudePermissionDefaults.data;
  message = "Destructive commands name literal paths, never shell variables; rewrite the path as a literal and run again.";
in
pkgs.runCommand "claude-permission-request-hook"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    export HOME="$TMPDIR/home"
    export XDG_STATE_HOME="$HOME/.local/state"
    export DRY_RUN_CMD=""
    mkdir -p "$HOME/.claude"
    cat > "$HOME/.claude/settings.json" <<'JSON'
    {"permissions":{"allow":["Bash(ls *)"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"herdr-agent-state.sh session"}]}]}}
    JSON

    # The managed merge, exactly as activation runs it.
    ${mergeSettings}

    settings="$HOME/.claude/settings.json"
    jq -e '.permissions.defaultMode == "bypassPermissions"' "$settings"
    jq -e '.permissions.allow == ["Bash(ls *)"]' "$settings"
    jq -e '.hooks.SessionStart[0].hooks[0].command == "herdr-agent-state.sh session"' "$settings"
    jq -e '.hooks.PermissionRequest | length == 1' "$settings"
    jq -e '.hooks.PermissionRequest[0].matcher == "Bash"' "$settings"
    hook="$(jq -r '.hooks.PermissionRequest[0].hooks[0].command' "$settings")"
    test -x "$hook"

    # A bypass Bash request (the dangerous-removal check) is denied.
    printf '%s' '{"session_id":"s-bypass","permission_mode":"bypassPermissions","hook_event_name":"PermissionRequest","tool_name":"Bash","cwd":"/w","tool_input":{"command":"S=/w/a; w=old; rm -rf $S/$w"}}' \
      | "$hook" > deny.json
    jq -e --arg message ${pkgs.lib.escapeShellArg message} '
      .hookSpecificOutput.hookEventName == "PermissionRequest"
      and .hookSpecificOutput.decision.behavior == "deny"
      and .hookSpecificOutput.decision.message == $message' deny.json

    # Outside bypass the hook records and leaves the ordinary prompt.
    printf '%s' '{"session_id":"s-default","permission_mode":"default","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf /w/x"}}' \
      | "$hook" > prompt.out
    test ! -s prompt.out

    # A malformed request still yields no decision and no failure.
    printf 'not json' | "$hook" > malformed.out
    test ! -s malformed.out

    log="$XDG_STATE_HOME/claude/permission-requests.jsonl"
    test "$(wc -l < "$log")" -eq 2
    jq -se '.[0] | .session == "s-bypass" and .decision == "deny" and .command == "S=/w/a; w=old; rm -rf $S/$w" and (.time | test("^[0-9-]+T[0-9:]+Z$"))' "$log"
    jq -se '.[1] | .session == "s-default" and .decision == "prompt"' "$log"

    cp "$log" "$out"
  ''
