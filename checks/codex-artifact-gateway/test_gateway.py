import importlib.util
import socket
import sys
import threading
import unittest


gateway_path = sys.argv.pop(1)
spec = importlib.util.spec_from_file_location("gateway", gateway_path)
gateway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gateway)


class Broker:
    def __init__(self):
        self.request = None

    def exchange(self, client):
        with client:
            payload = b""
            while not payload.endswith(b"\r\n\r\n"):
                payload += client.recv(4096)
            self.request = payload.decode("ascii")
            client.sendall(
                b"HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: 3\r\nConnection: close\r\n\r\npng"
            )


class GatewayContract(unittest.TestCase):
    def test_only_get_artifact_routes_are_accepted(self):
        self.assertEqual(gateway.parse_artifact_route("GET", "/v1/artifacts/report-7"), "report-7")
        for method, path in (
            ("POST", "/v1/artifacts/report-7"),
            ("GET", "/upload"),
            ("GET", "/v1/artifacts/../secret"),
            ("GET", "/v1/artifacts/report%2Fsecret"),
            ("GET", "/v1/artifacts//secret"),
        ):
            with self.subTest(method=method, path=path):
                with self.assertRaises(gateway.RouteRejected):
                    gateway.parse_artifact_route(method, path)

    def test_broker_resolves_opaque_capability_and_artifact_id(self):
        socket_path = self._temporary_socket_path()
        listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        listener.bind(socket_path)
        listener.listen(1)
        broker = Broker()
        thread = threading.Thread(target=lambda: broker.exchange(listener.accept()[0]))
        thread.start()
        result = gateway.request_artifact(socket_path, "Capability opaque-token-0007", "report-7")
        thread.join()
        listener.close()
        self.assertIn("GET /v1/artifacts/report-7 HTTP/1.1\r\n", broker.request)
        self.assertIn("Authorization: Capability opaque-token-0007\r\n", broker.request)
        self.assertEqual(result, (200, "image/png", b"png"))

    def test_capability_is_required_before_broker_access(self):
        with self.assertRaises(gateway.AuthenticationRequired):
            gateway.capability_authorization(None)
        with self.assertRaises(gateway.AuthenticationRequired):
            gateway.capability_authorization("Bearer abc")
        self.assertEqual(
            gateway.capability_authorization("Capability opaque-token-0007"),
            "Capability opaque-token-0007",
        )

    def test_listener_accepts_only_standard_tailnet_ranges(self):
        self.assertEqual(gateway.bind_address("100.64.0.12"), "100.64.0.12")
        self.assertEqual(gateway.bind_address("fd7a:115c:a1e0::12"), "fd7a:115c:a1e0::12")
        for address in ("127.0.0.1", "192.168.1.2", "8.8.8.8", "2001:4860:4860::8888"):
            with self.subTest(address=address):
                with self.assertRaises(Exception):
                    gateway.bind_address(address)
        self.assertEqual(gateway.port_number("8443"), 8443)
        for port in ("0", "65536"):
            with self.assertRaises(Exception):
                gateway.port_number(port)

    def _temporary_socket_path(self):
        import tempfile
        import os

        directory = tempfile.mkdtemp()
        socket_path = os.path.join(directory, "broker.sock")
        self.addCleanup(lambda: os.rmdir(directory))
        self.addCleanup(lambda: os.path.exists(socket_path) and os.unlink(socket_path))
        return socket_path


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
