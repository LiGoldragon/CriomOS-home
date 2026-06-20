#!/usr/bin/env python
"""Local-Gemma + CDP browser-use driver.

Runs ONE browser-use task against a Chrome that is already listening on a
Chrome DevTools Protocol url, using the workspace-local Gemma 4 multimodal
model as the vision LLM. This is the supervised-scout shape from report 61
(Spirit 7hmc/5g4d/7o4q): the agent attaches to a human-visible Chrome
(started on a non-default --user-data-dir per the Chrome-136+ rule) and
reads the page visually with the on-prem model — no cloud LLM, no
account screenshots leaving the cluster (Spirit u275/wvgh/8pgh).

Configuration comes entirely from the environment, set by the
`browser-use-local` wrapper, so no secrets land in argv:

  OPENAI_BASE_URL          local Gemma OpenAI-compatible endpoint (/v1)
  OPENAI_API_KEY           local-LLM token (sourced from gopass by the wrapper)
  BROWSER_USE_VISION_MODEL  model id, e.g. gemma-4-26b-a4b
  BROWSER_USE_CDP_URL      e.g. http://127.0.0.1:9222
  BROWSER_USE_TASK         natural-language task for the agent
  BROWSER_USE_LLM_TIMEOUT_SECONDS
                            OpenAI-compatible and browser-use agent LLM
                            request timeout; local Gemma vision prompts can
                            legitimately exceed browser-use's cloud-oriented
                            default.
  BROWSER_USE_USE_VISION   true/false; set false for DOM-only operation on
                            pages where browser-use clean screenshot capture
                            is unstable.
"""

import asyncio
import os
import sys

from browser_use import Agent, BrowserSession, ChatOpenAI


async def drive() -> int:
    base_url = os.environ.get("OPENAI_BASE_URL")
    api_key = os.environ.get("OPENAI_API_KEY")
    model = os.environ.get("BROWSER_USE_VISION_MODEL", "gemma-4-26b-a4b")
    cdp_url = os.environ.get("BROWSER_USE_CDP_URL")
    task = os.environ.get("BROWSER_USE_TASK")
    timeout_seconds_text = os.environ.get("BROWSER_USE_LLM_TIMEOUT_SECONDS", "240")
    use_vision_text = os.environ.get("BROWSER_USE_USE_VISION", "true").lower()
    use_vision = use_vision_text not in {"0", "false", "no", "off"}

    try:
        timeout_seconds = float(timeout_seconds_text)
    except ValueError:
        print(
            "browser-use-local: BROWSER_USE_LLM_TIMEOUT_SECONDS must be a number",
            file=sys.stderr,
        )
        return 2

    if not cdp_url or not task:
        print(
            "browser-use-local: BROWSER_USE_CDP_URL and BROWSER_USE_TASK are required",
            file=sys.stderr,
        )
        return 2
    if not base_url or not api_key:
        print(
            "browser-use-local: OPENAI_BASE_URL and OPENAI_API_KEY must point at the local Gemma endpoint",
            file=sys.stderr,
        )
        return 2

    # Vision LLM is the on-prem Gemma 4, reached over the OpenAI-compatible
    # local endpoint. Never a cloud provider.
    llm = ChatOpenAI(
        model=model,
        base_url=base_url,
        api_key=api_key,
        timeout=timeout_seconds,
    )

    # Attach to the already-running, human-visible Chrome over CDP. The
    # session is closed on exit; the human's browser process survives.
    session = BrowserSession(cdp_url=cdp_url)

    agent = Agent(
        task=task,
        llm=llm,
        browser_session=session,
        use_vision=use_vision,
        llm_timeout=int(timeout_seconds),
        step_timeout=max(180, int(timeout_seconds) + 60),
    )
    try:
        history = await agent.run(max_steps=12)
    finally:
        await session.kill()

    result = history.final_result() if hasattr(history, "final_result") else None
    if result:
        print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(drive()))
