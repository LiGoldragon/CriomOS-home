"""One approved Anthropic request. Prompt on stdin; credential on fd 3."""

import os
import sys

CREDENTIAL_FD = 3
PROMPT_BYTE_LIMIT = 2 * 1024 * 1024
CREDENTIAL_BYTE_LIMIT = 4096
ANTHROPIC_ENDPOINT = "https://api.anthropic.com"
HAIKU_FUNCTION_CHECK_MAX_TOKENS = 64
MODEL_PROCEDURES = ("opus-medium", "haiku-function-check")
PROCEDURE = "@procedure@"


def request_once(prompt, key, procedure, endpoint=ANTHROPIC_ENDPOINT):
    from llm_anthropic import ClaudeMessages, LATEST_MODEL_DEFAULTS

    if procedure == "opus-medium":
        model = ClaudeMessages(
            "claude-opus-5-5", base_url=endpoint, **LATEST_MODEL_DEFAULTS
        )
        options = {"thinking_effort": "medium"}
    elif procedure == "haiku-function-check":
        model = ClaudeMessages(
            "claude-haiku-4-5-20251001",
            base_url=endpoint,
            supports_pdf=True,
            supports_thinking=True,
            supports_web_search=True,
            supports_code_execution=True,
            use_structured_outputs=True,
            default_max_tokens=64000,
        )
        options = {"max_tokens": HAIKU_FUNCTION_CHECK_MAX_TOKENS}
    else:
        raise ValueError
    # Model.key is consulted before saved keys, aliases or the process env.
    model.key = key
    try:
        return model.prompt(prompt, stream=False, hide_reasoning=True, **options).text()
    finally:
        model.key = None


def read_credential():
    with os.fdopen(CREDENTIAL_FD, "rb") as credential:
        value = credential.read(CREDENTIAL_BYTE_LIMIT + 1)
    if len(value) > CREDENTIAL_BYTE_LIMIT:
        raise ValueError
    value = value.removesuffix(b"\n")
    if not value or not all(33 <= byte <= 126 for byte in value):
        raise ValueError
    return value.decode("ascii")


def main():
    # The derivation binds a fixed procedure into each executable.
    if len(sys.argv) != 1 or PROCEDURE not in MODEL_PROCEDURES:
        print("The Anthropic adapter accepts no caller arguments.", file=sys.stderr)
        return 2
    try:
        prompt = sys.stdin.buffer.read(PROMPT_BYTE_LIMIT + 1)
        if not prompt or len(prompt) > PROMPT_BYTE_LIMIT:
            raise ValueError
        prompt = prompt.decode("utf-8")
        key = read_credential()
    except (OSError, ValueError):
        print("Anthropic input or credential descriptor was refused.", file=sys.stderr)
        return 2
    # The SDK also accepts environment-configured custom headers and logging.
    # This process has exactly one approved credential and endpoint.
    for name in list(os.environ):
        if name == "SSLKEYLOGFILE" or name.startswith("ANTHROPIC_"):
            del os.environ[name]
    try:
        reply = request_once(prompt, key, PROCEDURE)
        if key in reply:
            raise ValueError
    except Exception:
        print("The Anthropic request did not complete.", file=sys.stderr)
        return 1
    print(reply)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
