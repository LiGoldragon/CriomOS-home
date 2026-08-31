import os
import socket
import subprocess
import sys
import tempfile
import threading


def serve(socket_path, lines):
    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    listener.bind(socket_path)
    listener.listen(1)

    def send_lines():
        connection, _ = listener.accept()
        with connection:
            for line in lines:
                connection.sendall(line.encode() + b"\n")
        listener.close()

    return listener, threading.Thread(target=send_lines, daemon=True)


def verify_stream(socat, luau, program, lines):
    with tempfile.TemporaryDirectory() as temporary_directory:
        socket_path = os.path.join(temporary_directory, "listener.sock")
        listener, sender = serve(socket_path, lines)
        sender.start()
        reader = subprocess.Popen(
            [socat, "-u", f"UNIX-CONNECT:{socket_path}", "STDOUT"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        interpreter = subprocess.run(
            [luau, program],
            stdin=reader.stdout,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=os.path.dirname(program),
            check=False,
        )
        sender.join(timeout=5)
        reader.wait(timeout=5)
        assert not sender.is_alive()
        assert interpreter.returncode == 0, interpreter.stderr.decode()


def main():
    socat, luau, program, scenario = sys.argv[1:]
    if scenario == "state":
        verify_stream(
            socat,
            luau,
            program,
            [
                "MODE transcript",
                'EVENT {"session":"test-session","revision":2,"kind":"partial","text":"Synthetic first"}',
                'EVENT {"session":"test-session","revision":1,"kind":"partial","text":"Stale"}',
                'EVENT {"session":"test-session","revision":3,"kind":"partial","text":"Synthetic second"}',
                'EVENT {"session":"test-session","revision":4,"kind":"final","text":"Synthetic final"}',
                'EVENT {"session":"test-session","revision":5,"kind":"closed","text":""}',
            ],
        )
        verify_stream(
            socat,
            luau,
            program,
            [
                "MODE status",
                'STATUS {"state":"recording","level":0.2,"in_flight":0,"text":"Synthetic status leak"}',
            ],
        )
    elif scenario == "level":
        verify_stream(
            socat,
            luau,
            program,
            [
                '{"session":"test-session","revision":2,"kind":"partial","text":"Synthetic first"}',
                '{"session":"test-session","revision":1,"kind":"partial","text":"Stale"}',
                '{"session":"test-session","revision":3,"kind":"final","text":"Synthetic final"}',
                '{"session":"test-session","revision":4,"kind":"closed","text":""}',
            ],
        )
    else:
        raise AssertionError(f"unknown scenario: {scenario}")


if __name__ == "__main__":
    main()
