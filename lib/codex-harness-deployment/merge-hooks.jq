def object_required($name):
  if type == "object" then . else error($name + " must be an object") end;

def our_hook:
  type == "object" and .type == "command"
  and ((.command // "") | type == "string" and contains($marker));

def without_owned_hooks:
  if type == "array" then
    map(
      if type == "object" and (.hooks | type) == "array" and any(.hooks[]; our_hook) then
        .hooks |= map(select(our_hook | not)) | select((.hooks | length) > 0)
      else . end
    )
  else . end;

object_required("Codex hooks document")
| .hooks = ((.hooks // {}) | object_required("Codex hooks table"))
| .hooks |= with_entries(.value |= without_owned_hooks)
| reduce $events[] as $event (.;
    .hooks[$event] |= (
      (. // [])
      | if type != "array" then error("Codex event hooks must be an array") else . end
      | . + [{hooks: [{type: "command", command: $command, timeout: $timeout}]}]
    ))
