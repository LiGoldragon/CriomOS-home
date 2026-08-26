import base64
import hashlib
import json
import os
import socket
import struct
import sys


def receive_exactly(connection, size):
    content = b""
    while len(content) < size:
        fragment = connection.recv(size - len(content))
        if not fragment:
            raise RuntimeError("app-server closed the connection before initialize completed")
        content += fragment
    return content


def receive_until(connection, marker):
    content = b""
    while marker not in content:
        fragment = connection.recv(4096)
        if not fragment:
            raise RuntimeError("app-server closed the HTTP upgrade response")
        content += fragment
    return content


def send_frame(connection, payload):
    mask = os.urandom(4)
    header = bytes([0x81])
    if len(payload) < 126:
        header += bytes([0x80 | len(payload)])
    elif len(payload) < 65536:
        header += bytes([0x80 | 126]) + struct.pack("!H", len(payload))
    else:
        header += bytes([0x80 | 127]) + struct.pack("!Q", len(payload))
    masked = bytes(value ^ mask[index % 4] for index, value in enumerate(payload))
    connection.sendall(header + mask + masked)


def receive_frame(connection):
    first, second = receive_exactly(connection, 2)
    opcode = first & 0x0F
    size = second & 0x7F
    if size == 126:
        size = struct.unpack("!H", receive_exactly(connection, 2))[0]
    elif size == 127:
        size = struct.unpack("!Q", receive_exactly(connection, 8))[0]
    if second & 0x80:
        mask = receive_exactly(connection, 4)
        payload = bytes(value ^ mask[index % 4] for index, value in enumerate(receive_exactly(connection, size)))
    else:
        payload = receive_exactly(connection, size)
    if opcode == 0x8:
        raise RuntimeError("app-server closed the websocket during initialize")
    if opcode != 0x1:
        raise RuntimeError(f"unexpected websocket opcode {opcode}")
    return payload


def connect(socket_path):
    websocket_key = base64.b64encode(os.urandom(16)).decode()
    request = (
        "GET / HTTP/1.1\r\n"
        "Host: localhost\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {websocket_key}\r\n"
        "Sec-WebSocket-Version: 13\r\n\r\n"
    ).encode()
    connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    connection.connect(socket_path)
    connection.sendall(request)
    response = receive_until(connection, b"\r\n\r\n")
    accept = base64.b64encode(hashlib.sha1((websocket_key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    normalized_response = response.lower()
    if b"http/1.1 101" not in normalized_response or f"sec-websocket-accept: {accept}".encode().lower() not in normalized_response:
        raise RuntimeError("app-server rejected the websocket upgrade")
    return connection


def initialize(connection, request_id, codex_home):
    send_frame(
        connection,
        json.dumps(
            {
                "id": request_id,
                "method": "initialize",
                "params": {"clientInfo": {"name": "criomos-home-check", "version": "1"}},
            }
        ).encode(),
    )
    while True:
        message = json.loads(receive_frame(connection))
        if message.get("id") == request_id:
            if message.get("result", {}).get("codexHome") != codex_home:
                raise RuntimeError("initialize reported a different CODEX_HOME")
            break
    send_frame(connection, json.dumps({"method": "initialized", "params": {}}).encode())


def main():
    socket_path, codex_home = sys.argv[1:]
    connections = [connect(socket_path), connect(socket_path)]
    for request_id, connection in enumerate(connections, start=1):
        initialize(connection, request_id, codex_home)


if __name__ == "__main__":
    main()
