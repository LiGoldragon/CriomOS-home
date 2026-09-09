#!/usr/bin/env python3
"""TLS gateway from a Tailnet address to a capability-aware Unix broker."""

import argparse
import http.client
import http.server
import ipaddress
import re
import socket
import ssl
import urllib.parse


ARTIFACT_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9._~-]{0,255}")
CAPABILITY = re.compile(r"Capability ([A-Za-z0-9._~-]{16,1024})")
MAX_RESPONSE_BYTES = 64 * 1024 * 1024
TAILNET_NETWORKS = (
    ipaddress.ip_network("100.64.0.0/10"),
    ipaddress.ip_network("fd7a:115c:a1e0::/48"),
)


class RouteRejected(ValueError):
    pass


class AuthenticationRequired(ValueError):
    pass


def parse_artifact_route(method, target):
    if method != "GET":
        raise RouteRejected("only GET is supported")
    parsed = urllib.parse.urlsplit(target)
    if parsed.query or parsed.fragment:
        raise RouteRejected("query strings and fragments are not accepted")
    prefix = "/v1/artifacts/"
    if not parsed.path.startswith(prefix):
        raise RouteRejected("unknown route")
    encoded_id = parsed.path[len(prefix) :]
    artifact_id = urllib.parse.unquote(encoded_id)
    if encoded_id != urllib.parse.quote(artifact_id, safe="._~-"):
        raise RouteRejected("artifact ID must use its canonical URL form")
    if ARTIFACT_ID.fullmatch(artifact_id) is None:
        raise RouteRejected("invalid artifact ID")
    return artifact_id


def capability_authorization(header):
    if header is None or CAPABILITY.fullmatch(header) is None:
        raise AuthenticationRequired("Authorization: Capability is required")
    return header


def request_artifact(broker_socket, authorization, artifact_id):
    capability_authorization(authorization)
    request_target = "/v1/artifacts/" + urllib.parse.quote(artifact_id, safe="._~-")
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.settimeout(10)
    try:
        connection.connect(broker_socket)
        request = (
            f"GET {request_target} HTTP/1.1\r\n"
            "Host: capability-artifact-broker\r\n"
            f"Authorization: {authorization}\r\n"
            "Connection: close\r\n\r\n"
        )
        connection.sendall(request.encode("ascii"))
        response = http.client.HTTPResponse(connection)
        response.begin()
        body = response.read(MAX_RESPONSE_BYTES + 1)
        if len(body) > MAX_RESPONSE_BYTES:
            raise RuntimeError("broker response exceeds gateway limit")
        return response.status, response.getheader("Content-Type", "application/octet-stream"), body
    finally:
        connection.close()


class GatewayHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "CodexArtifactGateway/1"

    def do_GET(self):
        try:
            artifact_id = parse_artifact_route("GET", self.path)
            authorization = capability_authorization(self.headers.get("Authorization"))
            status, content_type, body = request_artifact(
                self.server.broker_socket, authorization, artifact_id
            )
        except AuthenticationRequired as error:
            self._reply(401, "text/plain; charset=utf-8", str(error).encode())
            return
        except RouteRejected as error:
            self._reply(404, "text/plain; charset=utf-8", str(error).encode())
            return
        except (ConnectionError, OSError, http.client.HTTPException):
            self._reply(502, "text/plain; charset=utf-8", b"artifact broker unavailable")
            return
        self._reply(status, content_type, body)

    def do_POST(self):
        self._reply(405, "text/plain; charset=utf-8", b"uploads are not supported")

    def _reply(self, status, content_type, body):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, message, *args):
        return


class GatewayServer(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, broker_socket):
        self.broker_socket = broker_socket
        if ":" in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, GatewayHandler)


def bind_address(value):
    address = ipaddress.ip_address(value)
    if not any(address in network for network in TAILNET_NETWORKS):
        raise argparse.ArgumentTypeError("bind address must be in a standard Tailnet address range")
    return str(address)


def port_number(value):
    port = int(value)
    if not 1 <= port <= 65535:
        raise argparse.ArgumentTypeError("port must be between 1 and 65535")
    return port


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--bind-address", required=True, type=bind_address)
    parser.add_argument("--port", required=True, type=port_number)
    parser.add_argument("--tls-certificate", required=True)
    parser.add_argument("--tls-private-key", required=True)
    parser.add_argument("--broker-socket", required=True)
    args = parser.parse_args()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.load_cert_chain(args.tls_certificate, args.tls_private_key)
    server = GatewayServer((args.bind_address, args.port), args.broker_socket)
    server.socket = context.wrap_socket(server.socket, server_side=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
