"""Local real-Unison fixtures; no SSH, credential, or live user tree access."""
import pathlib
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    master, replica = root / "master", root / "replica"
    master.mkdir()
    replica.mkdir()
    (master / "file").write_text("initial master\n")
    (master / ".git").mkdir()
    (master / ".git" / "fixture").write_text("version control is carried\n")
    (master / "target").mkdir()
    (master / "target" / "build").write_text("local build only\n")
    (master / "link").symlink_to("file")
    command = [sys.argv[1], str(master), str(replica), "-batch", "-prefer", str(master), "-times", "false"]
    for ignored in ["target", "result", ".direnv"]:
        command += ["-ignore", "Name " + ignored]
    def synchronize():
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        if result.returncode:
            print(result.stdout.decode(errors="replace"))
            result.check_returncode()
    synchronize()
    assert (replica / "file").read_text() == "initial master\n"
    assert (replica / ".git" / "fixture").is_file()
    assert not (replica / "target").exists()
    assert (replica / "link").is_symlink()
    (replica / "from-replica").write_text("replica writes travel back\n")
    synchronize()
    assert (master / "from-replica").read_text() == "replica writes travel back\n"
    (master / "file").write_text("master conflict winner\n")
    (replica / "file").write_text("replica competing contents with different size\n")
    synchronize()
    assert (replica / "file").read_text() == "master conflict winner\n"
    print("real Unison: bidirectional changes, master conflict preference, VCS, ignored builds, symlinks passed")
