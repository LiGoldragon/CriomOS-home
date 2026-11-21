import glob
import os
import pathlib
import re
import socket
import struct
import subprocess
import sys

launcher, interpreter = sys.argv[1:]
notification = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
notification.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
notification.bind(str(pathlib.Path("notify.socket").absolute()))
notification.settimeout(60)
environment = dict(os.environ, NOTIFY_SOCKET=notification.getsockname())
process = subprocess.Popen([launcher], env=environment, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True)
message, ancillary, _, _ = notification.recvmsg(4096, socket.CMSG_SPACE(12))
assert message == b"READY=1", message
sender = next(struct.unpack("3i", data)[0] for level, kind, data in ancillary
              if level == socket.SOL_SOCKET and kind == socket.SCM_CREDENTIALS)
output, _ = process.communicate(timeout=60)
assert process.returncode == 0, output
target = int(re.search(r"TARGET_PID (\d+)", output)[1])
assert sender == target and target != process.pid, (sender, target, process.pid)
directory = pathlib.Path("profile")
assert directory.stat().st_uid == os.getuid()
assert directory.stat().st_mode & 0o777 == 0o700
traces = glob.glob("profile/heaptrack.*")
assert len(traces) == 1, traces
assert pathlib.Path(traces[0]).stat().st_mode & 0o777 == 0o600
report = subprocess.run([interpreter, traces[0]], check=True, capture_output=True,
                        text=True, timeout=60)
assert "retain_profile_memory" in report.stdout, report.stdout
print("PASS startup preload, unprofiled exec child, child READY credentials, private trace and named allocation stack")
