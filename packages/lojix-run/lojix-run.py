#!@python@
import datetime
import hashlib
import os
import pathlib
import re
import shlex
import subprocess
import sys

DEFAULT_LOJIX = "@lojix@"
DEFAULT_SSH = "@ssh@"
DEFAULT_JJ = "@jj@"

STORE_HASH_PATTERN = re.compile(r"/nix/store/[0-9a-z]+-")
HOME_GENERATION_PATTERN = re.compile(
    r"copying path '(/nix/store/[^']+-home-manager-generation)'"
)


class Request:
    def __init__(self, text):
        self.original_text = text
        self.text = ExactReferenceRewriter(DEFAULT_JJ).rewrite(text)
        self.tokens = NotaTokenizer(self.text).tokens()
        self.head = self.tokens[0] if self.tokens else "Unknown"

    def field(self, index):
        try:
            return self.tokens[index + 1]
        except IndexError:
            return None

    def cluster(self):
        return self.field(0)

    def node(self):
        return self.field(1)

    def user(self):
        if self.head == "HomeOnly":
            return self.field(2)
        return None

    def action(self):
        if self.head in {"FullOs", "OsOnly"}:
            return self.field(4)
        return None

    def mode(self):
        if self.head == "HomeOnly":
            return self.field(5)
        return None

    def target_domain(self):
        cluster = self.cluster()
        node = self.node()
        if cluster and node:
            return f"{node}.{cluster}.criome"
        return None


class NotaTokenizer:
    def __init__(self, text):
        self.text = text.strip()

    def tokens(self):
        text = self.text
        if text.startswith("(") and text.endswith(")"):
            text = text[1:-1]
        tokens = []
        index = 0
        while index < len(text):
            character = text[index]
            if character.isspace():
                index += 1
                continue
            if character == "[":
                token, index = self.bracket_token(text, index)
                tokens.append(token)
                continue
            start = index
            while index < len(text) and not text[index].isspace():
                index += 1
            tokens.append(text[start:index])
        return tokens

    def bracket_token(self, text, start):
        if text.startswith("[|", start):
            end = text.find("|]", start + 2)
            if end == -1:
                return text[start:], len(text)
            return text[start + 2:end], end + 2
        end = text.find("]", start + 1)
        if end == -1:
            return text[start:], len(text)
        return text[start + 1:end], end + 1


class ExactReferenceRewriter:
    REPOSITORIES = {
        "github:LiGoldragon/CriomOS/main": "/git/github.com/LiGoldragon/CriomOS",
        "github:LiGoldragon/CriomOS-home/main": "/git/github.com/LiGoldragon/CriomOS-home",
    }

    def __init__(self, jj):
        self.jj = os.environ.get("LOJIX_RUN_JJ", jj)

    def rewrite(self, text):
        rewritten = text
        for reference, repository in self.REPOSITORIES.items():
            if reference not in rewritten:
                continue
            revision = self.revision(repository)
            if revision:
                exact_reference = f"{reference.removesuffix('/main')}?rev={revision}"
                rewritten = rewritten.replace(reference, exact_reference)
        return rewritten

    def revision(self, repository):
        if not pathlib.Path(repository).exists():
            return None
        command = [
            self.jj,
            "-R",
            repository,
            "log",
            "-r",
            "main",
            "--no-graph",
            "--template",
            "commit_id",
        ]
        try:
            completed = subprocess.run(
                command,
                check=True,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
        except Exception:
            return None
        revision = completed.stdout.strip()
        if re.fullmatch(r"[0-9a-f]{40}", revision):
            return revision
        return None


class RunDirectory:
    def __init__(self, request):
        state_root = os.environ.get("LOJIX_RUN_DIRECTORY")
        if not state_root:
            state_home = os.environ.get(
                "XDG_STATE_HOME", os.path.expanduser("~/.local/state")
            )
            state_root = os.path.join(state_home, "lojix-runs")
        stamp = datetime.datetime.now(datetime.UTC).strftime("%Y%m%d%H%M%S")
        leaf = f"{stamp}-{request.head.lower()}-{request.node() or 'unknown'}"
        self.path = pathlib.Path(state_root) / leaf
        self.path.mkdir(parents=True, exist_ok=True)
        self.stdout = self.path / "stdout.log"
        self.stderr = self.path / "stderr.log"
        self.request = self.path / "request.nota"
        self.rewritten_request = self.path / "rewritten-request.nota"
        self.root_fallback_stdout = self.path / "root-home-fallback-stdout.log"
        self.root_fallback_stderr = self.path / "root-home-fallback-stderr.log"

    def write_requests(self, request):
        self.request.write_text(request.original_text, encoding="utf-8")
        self.rewritten_request.write_text(request.text, encoding="utf-8")


class LojixRun:
    def __init__(self, request):
        self.request = request
        self.directory = RunDirectory(request)
        self.lojix = os.environ.get("LOJIX_RUN_LOJIX", DEFAULT_LOJIX)
        self.ssh = os.environ.get("LOJIX_RUN_SSH", DEFAULT_SSH)
        self.outcome_store_path = None
        self.root_fallback_used = False

    def run(self):
        self.directory.write_requests(self.request)
        completed = self.invoke_lojix()
        if completed.returncode != 0 and self.can_root_fallback():
            if self.run_root_home_fallback():
                self.root_fallback_used = True
                completed = subprocess.CompletedProcess(completed.args, 0)
        self.outcome_store_path = self.success_store_path()
        summary = Summary(
            self.request,
            self.directory,
            completed.returncode,
            self.outcome_store_path,
            self.root_fallback_used,
        )
        summary.print()
        if completed.returncode == 0:
            PostChecks(self.request, self.outcome_store_path, self.ssh).print()
            return 0
        FailureTail(self.directory).print()
        return completed.returncode

    def invoke_lojix(self):
        with self.directory.stdout.open("w", encoding="utf-8") as stdout:
            with self.directory.stderr.open("w", encoding="utf-8") as stderr:
                return subprocess.run(
                    [self.lojix, self.request.text],
                    stdout=stdout,
                    stderr=stderr,
                    text=True,
                )

    def success_store_path(self):
        try:
            text = self.directory.stdout.read_text(encoding="utf-8").strip()
        except FileNotFoundError:
            return None
        if text.startswith("/nix/store/") and "\n" not in text:
            return text
        if self.root_fallback_used:
            return self.home_generation_from_stderr()
        return None

    def can_root_fallback(self):
        return (
            self.request.head == "HomeOnly"
            and self.request.mode() in {"Profile", "Activate"}
            and self.home_generation_from_stderr()
        )

    def home_generation_from_stderr(self):
        try:
            text = self.directory.stderr.read_text(encoding="utf-8")
        except FileNotFoundError:
            return None
        matches = HOME_GENERATION_PATTERN.findall(text)
        return matches[-1] if matches else None

    def run_root_home_fallback(self):
        target_domain = self.request.target_domain()
        user = self.request.user()
        generation = self.home_generation_from_stderr()
        if not target_domain or not user or not generation:
            return False
        script = RootHomeFallbackScript(user, generation, self.request.mode()).text()
        with self.directory.root_fallback_stdout.open("w", encoding="utf-8") as stdout:
            with self.directory.root_fallback_stderr.open("w", encoding="utf-8") as stderr:
                completed = subprocess.run(
                    [self.ssh, "-o", "BatchMode=yes", f"root@{target_domain}", script],
                    stdout=stdout,
                    stderr=stderr,
                    text=True,
                )
        return completed.returncode == 0


class RootHomeFallbackScript:
    def __init__(self, user, generation, mode):
        self.user = user
        self.generation = generation
        self.mode = mode

    def environment_text(self):
        return " ".join(
            [
                "env",
                "-i",
                f"HOME=/home/{self.user}",
                f"USER={self.user}",
                f"LOGNAME={self.user}",
                "SHELL=/run/current-system/sw/bin/bash",
                f"PATH=/home/{self.user}/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin",
                'XDG_RUNTIME_DIR="$run"',
                'DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus"',
            ]
        )

    def text(self):
        user = shlex.quote(self.user)
        generation = shlex.quote(self.generation)
        environment = self.environment_text()
        activation = f"runuser -u {user} -- {environment} {generation}/activate"
        return "\n".join(
            [
                "set -euo pipefail",
                f"uid=$(id -u {user})",
                "run=/run/user/$uid",
                f"test -x {generation}/activate",
                (
                    f"runuser -u {user} -- {environment} "
                    f"nix-env -p /home/{self.user}/.local/state/nix/profiles/home-manager "
                    f"--set {generation}"
                ),
                activation if self.mode == "Activate" else "true",
            ]
        )


class Summary:
    def __init__(self, request, directory, status, store_path, root_fallback_used):
        self.request = request
        self.directory = directory
        self.status = status
        self.store_path = store_path
        self.root_fallback_used = root_fallback_used

    def print(self):
        print(f"lojix_run={'success' if self.status == 0 else 'failed'}")
        print(f"request_kind={self.request.head}")
        if self.request.cluster():
            print(f"cluster={self.request.cluster()}")
        if self.request.node():
            print(f"node={self.request.node()}")
        if self.request.user():
            print(f"user={self.request.user()}")
        if self.request.action():
            print(f"action={self.request.action()}")
        if self.request.mode():
            print(f"mode={self.request.mode()}")
        if self.request.original_text != self.request.text:
            print("exact_reference_rewrite=yes")
        print(f"run_directory={self.directory.path}")
        for name, path in [("stdout", self.directory.stdout), ("stderr", self.directory.stderr)]:
            print(f"{name}_lines={LineCount(path).count()}")
            print(f"{name}_sha256={FileHash(path).digest()}")
        if self.root_fallback_used:
            print("root_home_fallback=success")


class PostChecks:
    def __init__(self, request, store_path, ssh):
        self.request = request
        self.store_path = store_path
        self.ssh = ssh

    def print(self):
        if not self.store_path or not self.request.target_domain():
            return
        if self.request.head in {"FullOs", "OsOnly"}:
            if self.request.action() in {"Boot", "Switch", "Test", "BootOnce"}:
                self.print_system_checks()
        if self.request.head == "HomeOnly":
            if self.request.mode() in {"Profile", "Activate"}:
                self.print_home_checks()

    def print_system_checks(self):
        script = "\n".join(
            [
                "set -euo pipefail",
                f"deploy={shlex.quote(self.store_path)}",
                (
                    'if [ "$(readlink -f /nix/var/nix/profiles/system)" = "$deploy" ]; '
                    "then echo system_profile_matches_deploy=yes; "
                    "else echo system_profile_matches_deploy=no; fi"
                ),
                (
                    'if [ "$(readlink -f /run/current-system)" = "$deploy" ]; '
                    "then echo current_system_matches_deploy=yes; "
                    "else echo current_system_matches_deploy=no; fi"
                ),
            ]
        )
        self.remote_print(script)

    def print_home_checks(self):
        user = self.request.user()
        if not user:
            return
        script = "\n".join(
            [
                "set -euo pipefail",
                f"deploy={shlex.quote(self.store_path)}",
                f"user={shlex.quote(user)}",
                'uid=$(id -u "$user")',
                'run=/run/user/$uid',
                (
                    'if [ "$(readlink -f /home/$user/.local/state/nix/profiles/home-manager)" '
                    '= "$deploy" ]; then echo home_profile_matches_deploy=yes; '
                    "else echo home_profile_matches_deploy=no; fi"
                ),
                (
                    'failed=$(systemctl --user -M "$user@" --failed --no-legend '
                    "2>/dev/null | wc -l || true)"
                ),
                'echo failed_user_units="$failed"',
                self.niri_reload_script(),
                (
                    'if [ -L "/home/$user/.pi/agent/packages/pi-continue" ]; '
                    "then echo pi_continue_symlink=yes; "
                    "else echo pi_continue_symlink=no; fi"
                ),
            ]
        )
        self.remote_print(script)

    def niri_reload_script(self):
        return "\n".join(
            [
                'if pgrep -u "$user" -x niri >/dev/null 2>&1; then',
                (
                    "  socket=$(find \"$run\" -maxdepth 2 -type s "
                    "\\( -name 'niri*.sock' -o -name '*niri*sock' \\) "
                    "2>/dev/null | head -1 || true)"
                ),
                '  if [ -n "$socket" ]; then',
                (
                    '    runuser -u "$user" -- env -i HOME=/home/$user '
                    'USER=$user LOGNAME=$user '
                    'PATH=/home/$user/.nix-profile/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin '
                    'XDG_RUNTIME_DIR="$run" '
                    'DBUS_SESSION_BUS_ADDRESS="unix:path=$run/bus" '
                    'NIRI_SOCKET="$socket" '
                    'niri msg action load-config-file '
                    '>/tmp/lojix-run-niri.out 2>/tmp/lojix-run-niri.err '
                    '&& echo niri_reload=success || echo niri_reload=failed'
                ),
                "  else",
                "    echo niri_reload=no_socket",
                "  fi",
                "else",
                "  echo niri_reload=skipped_no_process",
                "fi",
            ]
        )

    def remote_print(self, script):
        target = f"root@{self.request.target_domain()}"
        completed = subprocess.run(
            [self.ssh, "-o", "BatchMode=yes", target, script],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        if completed.returncode == 0:
            print(completed.stdout.rstrip())
        else:
            print("postcheck=failed")
            print(Redactor.redact(completed.stderr).rstrip())


class FailureTail:
    def __init__(self, directory):
        self.directory = directory

    def print(self):
        print("stdout_tail:")
        print(Redactor.tail(self.directory.stdout, 80))
        print("stderr_tail:")
        print(Redactor.tail(self.directory.stderr, 160))


class Redactor:
    @staticmethod
    def redact(text):
        return STORE_HASH_PATTERN.sub("/nix/store/<hash>-", text)

    @staticmethod
    def tail(path, lines):
        try:
            content = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except FileNotFoundError:
            return ""
        return Redactor.redact("\n".join(content[-lines:]))


class LineCount:
    def __init__(self, path):
        self.path = path

    def count(self):
        try:
            return sum(1 for _ in self.path.open("rb"))
        except FileNotFoundError:
            return 0


class FileHash:
    def __init__(self, path):
        self.path = path

    def digest(self):
        digest = hashlib.sha256()
        try:
            with self.path.open("rb") as handle:
                for chunk in iter(lambda: handle.read(65536), b""):
                    digest.update(chunk)
        except FileNotFoundError:
            pass
        return digest.hexdigest()


class RequestSource:
    def __init__(self, argument):
        self.argument = argument

    def text(self):
        stripped = self.argument.lstrip()
        if stripped.startswith("("):
            return self.argument
        return pathlib.Path(self.argument).read_text(encoding="utf-8")


def main():
    if len(sys.argv) != 2:
        print(
            "error: lojix-run takes exactly one NOTA request or request file path",
            file=sys.stderr,
        )
        return 2
    try:
        request = Request(RequestSource(sys.argv[1]).text())
        return LojixRun(request).run()
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
