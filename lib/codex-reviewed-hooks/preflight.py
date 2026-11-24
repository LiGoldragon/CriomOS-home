"""Emit read-only evidence for the fixed, reviewed plain Codex transition."""

import json
from pathlib import Path
import sys

from transition import Refusal, observe


if __name__ == "__main__":
    try:
        with observe(Path(sys.argv[1])) as (_, evidence, _, _):
            pass
        print(json.dumps(evidence))
    except Refusal as error:
        sys.exit(f"Codex hook preflight: {error}")
    except Exception as error:
        sys.exit(f"Codex hook preflight could not verify its inputs or reply ({type(error).__name__}).")
