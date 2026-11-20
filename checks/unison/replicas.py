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
    command = [sys.argv[1], str(master), str(replica), "-batch", "-prefer", str(master), "-times=false"]
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

# Exercise Unison's own sshargs parsing, using a fixture program that cannot
# open a network connection. No production daemon or user directory is used.
import json
import os
with tempfile.TemporaryDirectory() as temporary:
    root = pathlib.Path(temporary)
    agent = root / "agent.sock"
    captured = root / "arguments.json"
    fake = root / "ssh"
    fake.write_text("#!" + sys.executable + "\nimport json,os,pathlib,sys\npathlib.Path(os.environ['UNISON_FIXTURE_ARGUMENTS']).write_text(json.dumps(sys.argv[1:]))\nsys.exit(1)\n")
    fake.chmod(0o700)
    profiles = pathlib.Path(os.environ["HOME"]) / ".unison"
    profiles.mkdir(exist_ok=True)
    profile = pathlib.Path(sys.argv[2]).read_text()
    profile = profile.replace("sshcmd = " + sys.argv[3], "sshcmd = " + str(fake))
    profile = profile.replace("/home/example/code", str(root / "tree"))
    (root / "tree").mkdir()
    (profiles / "closed-ssh.prf").write_text(profile)
    environment = dict(os.environ, SSH_AUTH_SOCK=str(agent), UNISON_FIXTURE_ARGUMENTS=str(captured))
    failed = subprocess.run([sys.argv[1], "closed-ssh"], env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    assert failed.returncode != 0
    arguments = json.loads(captured.read_text())
    for argument in ["-F", "none", "-oBatchMode=yes", "-oIdentityAgent=SSH_AUTH_SOCK", "-oIdentityFile=none", "-oUserKnownHostsFile=none", "-oGlobalKnownHostsFile=/etc/ssh/ssh_known_hosts", "-oStrictHostKeyChecking=yes", "-oPreferredAuthentications=publickey"]:
        assert argument in arguments, arguments
    # -G resolves options without authenticating or opening a connection.
    server_program = next(line.removeprefix("servercmd = ") for line in profile.splitlines() if line.startswith("servercmd = "))
    options = arguments[:arguments.index(server_program)]
    if "-l" in options:
        # Unison supplies the declared user explicitly; retain it for -G.
        assert options[options.index("-l") + 1] == "example"
    effective = subprocess.run([sys.argv[3], "-G"] + options, env=environment, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30).stdout.decode()
    for setting in ["batchmode yes", "identityfile none", "userknownhostsfile none", "globalknownhostsfile /etc/ssh/ssh_known_hosts", "stricthostkeychecking true", "preferredauthentications publickey"]:
        assert setting in effective, (setting, effective)
    print("closed SSH: exact Unison argument delivery and non-network OpenSSH effective configuration passed")
