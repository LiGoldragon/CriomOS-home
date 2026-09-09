import importlib.util
import sys


gateway_path, socket_path, token = sys.argv[1:]
spec = importlib.util.spec_from_file_location("gateway", gateway_path)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)

status, content_type, body = gateway.request_artifact(
    socket_path, f"Capability {token}", "artifact-1"
)
assert (status, content_type, body) == (
    200,
    "text/plain",
    b"synthetic broker artifact",
)

denied_status, _, denied_body = gateway.request_artifact(
    socket_path, "Capability invalid-token-0000", "artifact-1"
)
assert denied_status in (401, 403)
assert b"synthetic broker artifact" not in denied_body
