#!/usr/bin/env bash
# Test one built image: host-side contract + secret checks, then the image's own
# test.sh four ways: as the default user; as uid 1000 with an unfamiliar HOME; and with
# the flags Hermes's docker backend uses (caps dropped, no-new-privileges, tmpfs over
# /tmp /run /home /root) in a login shell like Hermes's, as root and as uid 1000.
#
#   scripts/test-image.sh <image>-<distro>       e.g. scripts/test-image.sh dev-alpine
#
# Env: REGISTRY (default ghcr.io/jamesjnadeau/hermes-workers), EXPECT_SDK (passed through).
set -euo pipefail

target=${1:?usage: $0 <image>-<distro>}
image=${target%-*}
distro=${target##*-}
registry=${REGISTRY:-ghcr.io/jamesjnadeau/hermes-workers}
root=$(cd "$(dirname "$0")/.." && pwd)

case "$target" in
  playdate-*) ref="hermes-workers/$image:$distro" ;;  # local-only, never in the registry
  *)          ref="$registry/$image:$distro" ;;
esac

test_file="$root/images/$image/$distro/test.sh"
[ -f "$test_file" ] || { echo "no test at $test_file" >&2; exit 2; }
docker image inspect "$ref" >/dev/null || { echo "image $ref not built" >&2; exit 2; }

fail=0
echo "== $ref: image contract"
cmd=$(docker image inspect -f '{{json .Config.Cmd}}' "$ref")
entry=$(docker image inspect -f '{{json .Config.Entrypoint}}' "$ref")
if [ "$cmd" = '["sleep","infinity"]' ]; then echo "  PASS  CMD is sleep infinity"; else echo "  FAIL  CMD is $cmd"; fail=1; fi
if [ "$entry" = null ] || [ "$entry" = '[]' ]; then echo "  PASS  no ENTRYPOINT"; else echo "  FAIL  ENTRYPOINT is $entry"; fail=1; fi

echo "== $ref: no secrets"
# Looks in env, labels and the full build history (which records ARGs and RUN lines) for:
#  - GitHub token formats (ghp_/gho_/ghu_/ghs_/ghr_, github_pat_) anywhere;
#  - credentials in URLs (scheme://user:pass@host);
#  - NAME=value where NAME's last segment is TOKEN, SECRET, PASSWORD, PASSWD, PAT, KEY or
#    CREDENTIALS and value is set (TOKEN_URL=... is fine; GIST_PAT=... is not).
# GPG_KEY is the Python base image's public release-signing key id.
# Then greps config-ish directories inside the image for GitHub token formats.
gh_tok='(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
hits=$( { docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' "$ref"
          docker history --no-trunc --format '{{.CreatedBy}}' "$ref"; } \
        | grep -Eo "$gh_tok|[a-z][a-z0-9+.-]*://[^/:@ ]+:[^/@ ]+@[^ ]+|[A-Za-z0-9_]*(^|_)(TOKEN|SECRET|PASSWORD|PASSWD|PAT|KEY|CREDENTIALS)=[^ \"]+" \
        | grep -Ev '^GPG_KEY=|=\$' || true)
file_hits=$(docker run --rm --entrypoint sh "$ref" -c \
  "grep -rEl '$gh_tok' /etc /root /home /var/lib/pn /usr/local/etc 2>/dev/null" || true)
[ -n "$file_hits" ] && hits=$(printf '%s\nfiles: %s' "$hits" "$file_hits")
if [ -z "$hits" ]; then echo "  PASS  no token/secret values in env, labels or history"; else echo "  FAIL  possible secrets:"; echo "$hits" | sed 's/^/        /'; fail=1; fi

# BASH_FLAGS=-l runs the test in a login shell. Hermes snapshots its environment from
# `bash -l`, and /etc/profile resets PATH, so tools found only through ENV PATH vanish there.
run_test() {
  docker run --rm "$@" \
    -e EXPECT_SDK="${EXPECT_SDK:-1}" \
    -v "$root/images:/images:ro" -v "$root/tests:/tests:ro" \
    "$ref" bash ${BASH_FLAGS:-} "/images/$image/$distro/test.sh"
}

echo "== $ref: test.sh (default user)"
run_test || fail=1
echo "== $ref: test.sh (uid 1000, HOME=/tmp/hermes-home)"
run_test --user 1000:1000 -e HOME=/tmp/hermes-home || fail=1

# Mirrors hermes-agent tools/environments/docker.py (non-persistent mode).
hermes_flags=(--cap-drop ALL --cap-add DAC_OVERRIDE --cap-add CHOWN --cap-add FOWNER
  --security-opt no-new-privileges
  --tmpfs /tmp:rw,nosuid,size=512m --tmpfs /var/tmp:rw,noexec,nosuid,size=256m
  --tmpfs /run:rw,noexec,nosuid,size=64m
  --tmpfs /home:rw,exec,size=1g --tmpfs /root:rw,exec,size=1g)
echo "== $ref: test.sh (Hermes flags, root, login shell)"
BASH_FLAGS=-l run_test "${hermes_flags[@]}" --cap-add SETUID --cap-add SETGID || fail=1
echo "== $ref: test.sh (Hermes flags, uid 1000, login shell)"
BASH_FLAGS=-l run_test "${hermes_flags[@]}" --user 1000:1000 || fail=1

[ "$fail" -eq 0 ] && echo "== $ref: OK" || echo "== $ref: FAILED"
exit "$fail"
