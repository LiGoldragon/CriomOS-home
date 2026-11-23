"""Wait for a socket creation event, or clear only inactive socket names."""

import ctypes
import os
import socket
import stat
import sys
from pathlib import Path


def clear(path):
    try:
        mode = path.lstat().st_mode
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(mode):
        raise RuntimeError(f"Not a socket: {path}")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as stream:
        stream.setblocking(False)
        try:
            stream.connect(os.fspath(path))
        except FileNotFoundError:
            return
        except ConnectionRefusedError:
            path.unlink(missing_ok=True)
            return
    raise RuntimeError(f"A listener already owns {path}")


def wait(path):
    libc = ctypes.CDLL(None, use_errno=True)
    descriptor = libc.inotify_init1(os.O_CLOEXEC)
    if descriptor < 0:
        raise OSError(ctypes.get_errno(), "open inotify")
    try:
        # Install the watch before looking: a bind that wins the race either
        # left a socket or queued an event.
        if libc.inotify_add_watch(descriptor, os.fsencode(path.parent), 0x100 | 0x80) < 0:
            raise OSError(ctypes.get_errno(), f"watch {path.parent}")
        while not path.is_socket():
            os.read(descriptor, 4096)
    finally:
        os.close(descriptor)


operation, *paths = sys.argv[1:]
match operation, paths:
    case "clear", paths:
        for path in paths:
            clear(Path(path))
    case "wait", [path]:
        wait(Path(path))
    case _:
        raise SystemExit("Usage: socket-readiness clear <paths...> | wait <path>")
