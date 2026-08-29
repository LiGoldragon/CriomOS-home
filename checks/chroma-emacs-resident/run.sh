set -euo pipefail

if [[ "${CHROMA_EMACS_RESIDENT_INSIDE:-}" != 1 ]]; then
  export CHROMA_EMACS_RESIDENT_INSIDE=1
  exec dbus-run-session --config-file="$CHROMA_EMACS_DBUS_SESSION_CONF" -- "$0" "$@"
fi

test_root="$(mktemp -d)"
cleanup() {
  [[ -n "${emacs_socket_name:-}" ]] && emacsclient --socket-name "$emacs_socket_name" --eval '(kill-emacs)' >/dev/null 2>&1 || true
  [[ -n "${chroma_pid:-}" ]] && kill "$chroma_pid" >/dev/null 2>&1 || true
  [[ -n "${gamma_pid:-}" ]] && kill "$gamma_pid" >/dev/null 2>&1 || true
}
trap cleanup EXIT

export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_RUNTIME_DIR="$test_root/runtime"
mkdir -p "$XDG_CONFIG_HOME/chroma" "$XDG_CONFIG_HOME/emacs-ignis-themes" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

cp "$CHROMA_EMACS_TEST_THEME_DIRECTORY"/ignis-dark-theme.el "$XDG_CONFIG_HOME/emacs-ignis-themes/"
cp "$CHROMA_EMACS_TEST_THEME_DIRECTORY"/ignis-light-theme.el "$XDG_CONFIG_HOME/emacs-ignis-themes/"
test -f "$CHROMA_EMACS_HOME_INIT_COMPILED/init.elc"
find "$CHROMA_EMACS_HOME_INIT_COMPILED/eln-cache" -type f -name '*.eln' | grep -q .
test "$(<"$CHROMA_EMACS_HOME_INIT_COMPILED/emacs-package-closure")" = "$CHROMA_EMACS_HOME_PACKAGE"

events="$test_root/events"
mkdir -p "$events"
coproc EVENT_WATCH { stdbuf -oL inotifywait --monitor --quiet --event close_write --format '%f' "$events"; }

await_event() {
  local received
  if ! IFS= read -r -t 20 -u "${EVENT_WATCH[0]}" received; then
    echo "timed out waiting for Emacs projection event" >&2
    return 1
  fi
  test "$received" = applied
}

cat > "$XDG_CONFIG_HOME/emacs-ignis-themes/chroma-test-overlay-theme.el" <<'EOF'
(deftheme chroma-test-overlay)
(custom-theme-set-faces
 'chroma-test-overlay
 '(mode-line ((t (:foreground "#ffffff" :background "#335577")))))
(provide-theme 'chroma-test-overlay)
EOF

cat > "$XDG_CONFIG_HOME/chroma/config.datom" <<'EOF'
{{[Terminal]
  {{#000000 #111111 #222222 #333333 #444444 #dddddd #eeeeee #ffffff #ff0000 #ff8800 #ffff00 #00ff00 #00ffff #0000ff #ff00ff #aa0000}
   {#f4f0e8 #e8e0d8 #ddd5ce #887a70 #6a5e55 #3d3530 #2a2420 #1a1510 #cc0044 #d06600 #b89000 #1a8a30 #9930cc #b03080 #8822bb #cc3355}}
  None Some.12 None None Manual.Light}
 {Manual.Neutral}
 {Manual.Bright}}
EOF

export CHROMA_SANDBOX_FAKE_GAMMA_READY="$test_root/gamma-ready"
chroma-emacs-test-gamma &
gamma_pid=$!
while [[ ! -e "$CHROMA_SANDBOX_FAKE_GAMMA_READY" ]]; do
  inotifywait --quiet --event create --event close_write "$(dirname "$CHROMA_SANDBOX_FAKE_GAMMA_READY")" >/dev/null
done

start_chroma() {
  chroma-daemon >"$test_root/chroma.log" 2>&1 &
  chroma_pid=$!
}

start_chroma
while [[ ! -S "$XDG_RUNTIME_DIR/chroma.sock" ]]; do
  inotifywait --quiet --event create "$XDG_RUNTIME_DIR" >/dev/null
done

cat > "$HOME/test-init.el" <<EOF
(load "$CHROMA_EMACS_TEST_THEME_INIT")
(advice-add 'chroma-theme--handle-snapshot :after
            (lambda (&rest _) (with-temp-file "$events/applied" (insert "applied"))))
(chroma-theme-mode 1)
EOF

start_emacs() {
  emacs_socket_name="$1"
  emacs --quick --daemon="$emacs_socket_name" --load "$HOME/test-init.el"
  emacsclient --socket-name "$emacs_socket_name" --eval '(progn (with-temp-file (expand-file-name "emacs-ready" (getenv "XDG_RUNTIME_DIR")) (insert "ready")) t)'
}

status_is_applied() {
  local revision="$1"
  local status
  status="$(gdbus call --session --dest io.github.LiGoldragon.Chroma \
    --object-path /io/github/LiGoldragon/Chroma/Theme \
    --method io.github.LiGoldragon.Chroma.Theme1.GetProjectionStatus emacs \
    )"
  echo "projection status: $status" >&2
  if ! grep -F "'Applied', uint64 $revision" <<<"$status" >/dev/null; then
    echo "expected Applied revision $revision, received: $status" >&2
    return 1
  fi
}

assert_emacs_state() {
  local expected_theme="$1"
  local opposite_theme="$2"
  local expected_background="$3"
  local expected_overlay="$4"
  local state
  state="$(emacsclient --socket-name "$emacs_socket_name" --eval \
    "(prin1-to-string (list (if (memq '$expected_theme custom-enabled-themes) t nil) (if (memq '$opposite_theme custom-enabled-themes) t nil) (if (memq 'chroma-test-overlay custom-enabled-themes) t nil) (face-attribute 'default :background nil t) (face-attribute 'mode-line :background nil t)))" \
    )"
  local expected_fragment="t nil $expected_overlay \\\"$expected_background\\\""
  if [[ "$expected_overlay" == t ]]; then
    expected_fragment+=" \\\"#335577\\\""
  fi
  if ! grep -F "$expected_fragment" <<<"$state" >/dev/null; then
    echo "expected Emacs state for $expected_theme, received: $state" >&2
    return 1
  fi
}

# Late startup: Chroma owns the bus before the resident Emacs daemon arrives.
start_emacs chroma-resident-one
await_event
status_is_applied 0
assert_emacs_state ignis-light ignis-dark '#faf5f0' nil

emacsclient --socket-name "$emacs_socket_name" --eval "(load-theme 'chroma-test-overlay t)" >/dev/null
chroma 'SetTheme.{Dark}' >/dev/null
await_event
status_is_applied 1
assert_emacs_state ignis-dark ignis-light '#000000' t

# Chroma restart: owner change must cause Emacs re-registration and snapshot reconciliation.
kill "$chroma_pid"
wait "$chroma_pid" || true
unset chroma_pid
start_chroma
await_event
status_is_applied 1
assert_emacs_state ignis-dark ignis-light '#000000' t

chroma 'SetTheme.{Light}' >/dev/null
await_event
status_is_applied 2
assert_emacs_state ignis-light ignis-dark '#faf5f0' t

# A new daemon instance represents an Emacs restart and must reconcile the current snapshot.
emacsclient --socket-name "$emacs_socket_name" --eval '(kill-emacs)' >/dev/null
emacs_socket_name=''
start_emacs chroma-resident-two
await_event
status_is_applied 2
assert_emacs_state ignis-light ignis-dark '#faf5f0' nil
