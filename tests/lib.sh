# Helpers sourced by images/*/*/test.sh inside the container under test.
# Failures accumulate; `finish` prints a summary and exits non-zero if anything failed.

_PASS=${_PASS:-0}
_FAIL=${_FAIL:-0}

_ok()  { _PASS=$((_PASS + 1)); printf '  PASS  %s\n' "$1"; }
_bad() { _FAIL=$((_FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# need CMD... : each command must be on PATH.
need() {
  local c
  for c in "$@"; do
    if command -v "$c" >/dev/null 2>&1; then _ok "have $c"; else _bad "missing $c"; fi
  done
}

# run DESC CMD... : CMD must exit 0. Output is shown only on failure.
run() {
  local desc=$1 out
  shift
  if out=$("$@" 2>&1); then
    _ok "$desc"
  else
    _bad "$desc"
    printf '%s\n' "$out" | tail -n 5 | sed 's/^/        /'
  fi
}

finish() {
  printf '%s passed, %s failed (uid %s)\n' "$_PASS" "$_FAIL" "$(id -u)"
  [ "$_FAIL" -eq 0 ]
  exit $?
}

# A parent test sourced with --no-finish must not exit.
_maybe_finish() {
  case " $* " in *" --no-finish "*) return 0 ;; esac
  finish
}
