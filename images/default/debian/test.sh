#!/usr/bin/env bash
# Smoke test for default:debian. Run by scripts/test-image.sh inside the image.
# Pass --no-finish when sourcing from a child image's test.
. /tests/lib.sh

need python3 pip uv node npm yarn git gh cargo rustc rustup jq rg fd tmux rsync zip \
     sqlite3 pandoc pdftotext yq shellcheck make cmake sudo

run "yq is mikefarah"      sh -c 'yq --version | grep -q mikefarah'
run "python is 3.13"       python3 -c 'import sys; assert sys.version_info[:2] == (3, 13)'
run "pillow imports"       python3 -c 'import PIL'
run "cargo home writable"  sh -c 'test -w /usr/local/cargo && test -w /usr/local/cargo/bin && test -w /usr/local/rustup'
run "rust compiles"        sh -c 'd=$(mktemp -d) && cd "$d" && cargo init -q --name t && cargo build -q --offline'
run "sbin dirs on PATH"   sh -c 'case ":$PATH:" in *:/usr/sbin:*) case ":$PATH:" in *:/sbin:*) ;; *) exit 1;; esac ;; *) exit 1;; esac'
run "pn user is 1000"      sh -c '[ "$(id -u pn)" = 1000 ]'
run "HOME is writable"     sh -c 'mkdir -p "$HOME/.cache/probe" && test -w "$HOME/.cache/probe"'
run "uv works"             sh -c 'd=$(mktemp -d) && cd "$d" && uv venv -q .venv'
run "npm cache works"      sh -c 'npm config get cache && npm cache verify >/dev/null'
# sudo can't work under no-new-privileges (Hermes sets it), so only check it outside Hermes.
if grep -q '^NoNewPrivs:[[:space:]]*1' /proc/self/status; then
  _ok "sudo skipped (no-new-privileges)"
else
  run "pn has nopasswd sudo" sh -c 'if [ "$(id -u)" = 0 ]; then su pn -c "sudo -n true"; else sudo -n true; fi'
fi
run "XDG_RUNTIME_DIR set"  test "${XDG_RUNTIME_DIR:-}" = /tmp/hermes-runtime
run "playwright browsers"  test "${PLAYWRIGHT_BROWSERS_PATH:-}" = /opt/playwright
run "chromium headless"    sh -c 'c=$(ls -d /opt/playwright/chromium-*/chrome-linux*/chrome | head -1); "$c" --headless --no-sandbox --disable-gpu --dump-dom "data:text/html,<title>ok</title>" 2>/dev/null | grep -q "<title>ok</title>"'
run "no github token"      test -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}"

_maybe_finish "$@"
