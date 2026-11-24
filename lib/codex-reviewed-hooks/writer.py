"""Apply the four reviewed plain Codex approvals against preflight evidence."""

import json
import os
from pathlib import Path
import sys
import tempfile
import tomllib

from transition import ReadOnlyCodex, Refusal, digest, observe, read_owned_file, require, verify_inventory


class ScopedWriter(ReadOnlyCodex):
    methods = ReadOnlyCodex.methods | {"config/batchWrite"}

    def approve(self, config_path, version, state, approved):
        edits = [
            {"keyPath": f"hooks.state.{json.dumps(key, ensure_ascii=False)}.trusted_hash",
             "value": digest, "mergeStrategy": "upsert"}
            for key, digest in approved.items()
            if state.get(key, {}).get("trusted_hash") != digest
        ]
        if edits:
            reply = self.request("config/batchWrite", {
                "filePath": str(config_path),
                "expectedVersion": version,
                "reloadUserConfig": False,
                "edits": edits,
            })
            require(
                reply.get("status") == "ok" and reply.get("filePath") == str(config_path),
                "Codex did not confirm the exact user-config write.",
            )


def replace_hooks(path, previous, document):
    pending_document = (json.dumps(document, ensure_ascii=False, indent=2) + "\n").encode()
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as temporary:
        pending = Path(temporary.name)
        try:
            temporary.write(pending_document)
            temporary.flush()
            os.fsync(temporary.fileno())
            require(read_owned_file(path) == previous, "The hook declarations changed during activation.")
            os.replace(pending, path)
        finally:
            pending.unlink(missing_ok=True)
    return pending_document


def reconcile(plan_path, receipt):
    with observe(plan_path, ScopedWriter) as (codex, evidence, revalidate, transition):
        require(evidence == receipt, "The preflight receipt no longer matches the owning peer, plan, user layer or hook files.")
        config_path, hooks_path, config, hooks_bytes, state, current, candidate, after = transition
        revalidate()
        if candidate != current:
            hooks_bytes = replace_hooks(hooks_path, hooks_bytes, candidate)
        verify_inventory(codex, hooks_path.parent, hooks_path, after)
        require(
            digest(read_owned_file(config_path)) == receipt["configDigest"]
            and read_owned_file(hooks_path) == hooks_bytes,
            "A hook file changed before the config write.",
        )
        codex.approve(config_path, evidence["userLayer"]["version"], state, after)
        approved_state = config.setdefault("hooks", {}).setdefault("state", {})
        for key, approved_hash in after.items():
            approved_state.setdefault(key, {})["trusted_hash"] = approved_hash
        require(
            tomllib.loads(read_owned_file(config_path).decode()) == config
            and read_owned_file(hooks_path) == hooks_bytes,
            "A hook file differs outside the reviewed changes.",
        )
        verify_inventory(codex, hooks_path.parent, hooks_path, after, target_status=True)


if __name__ == "__main__":
    try:
        reconcile(Path(sys.argv[1]), json.load(sys.stdin))
    except Refusal as error:
        sys.exit(f"Codex hook writer: {error}")
    except Exception as error:
        sys.exit(f"Codex hook writer could not verify its inputs or reply ({type(error).__name__}).")
