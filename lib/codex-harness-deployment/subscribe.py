"""Prove a subscription is accepted without exposing its snapshot."""

import subprocess
import sys

client = sys.argv[1]
with subprocess.Popen([client, "Subscribe"], stdout=subprocess.PIPE) as child:
    try:
        if not child.stdout.readline().startswith(b"Subscribed."):
            raise SystemExit("Codex Harness did not accept Subscribe.")
    finally:
        child.terminate()
