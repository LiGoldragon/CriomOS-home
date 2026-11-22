{
  pkgs,
  inputs,
  ...
}:
# llm 0.38 with llm-anthropic 0.31, from the pinned uv.lock in
# packages/llm-anthropic. Each Anthropic request is made once: the SDK and
# its HTTP transport retry nothing. llm-opus-medium and
# llm-haiku-function-check each take the prompt on stdin and the
# credential on inherited descriptor 3.
let
  llmAnthropic = pkgs.callPackage ../../../../packages/llm-anthropic {
    inherit inputs;
    generationOnce = true;
    includeCredentialAdapters = true;
  };
in
{
  home.packages = [ llmAnthropic ];
}
