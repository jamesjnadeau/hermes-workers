#!/usr/bin/env bash
# Test one built image: host-side contract + secret checks, then the image's own
# test.sh as the default user and again as uid 1000 with a fresh HOME (how Hermes
# runs it with docker_run_as_host_user).
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
# Env, labels and the full build history (which records ARGs and RUN lines).
# GPG_KEY is the Python base image's public release-signing key id.
hits=$( { docker image inspect -f '{{range .Config.Env}}{{println .}}{{end}}{{range $k, $v := .Config.Labels}}{{$k}}={{$v}}{{println}}{{end}}' "$ref"
          docker history --no-trunc --format '{{.CreatedBy}}' "$ref"; } \
        | grep -v '^GPG_KEY=' \
        | grep -Eio '(ghp_|github_pat_|gho_)[A-Za-z0-9_]+|[A-Z_]*(TOKEN|SECRET|PASSWORD)[A-Z_]*=[^ ]+' \
        | grep -Ev '=(\$|""|$)' || true)
if [ -z "$hits" ]; then echo "  PASS  no token/secret values in env, labels or history"; else echo "  FAIL  possible secrets:"; echo "$hits" | sed 's/^/        /'; fail=1; fi

run_test() {
  docker run --rm "$@" \
    -e EXPECT_SDK="${EXPECT_SDK:-1}" \
    -v "$root/images:/images:ro" -v "$root/tests:/tests:ro" \
    "$ref" bash "/images/$image/$distro/test.sh"
}

echo "== $ref: test.sh (default user)"
run_test || fail=1
echo "== $ref: test.sh (uid 1000, HOME=/tmp/hermes-home)"
run_test --user 1000:1000 -e HOME=/tmp/hermes-home || fail=1

[ "$fail" -eq 0 ] && echo "== $ref: OK" || echo "== $ref: FAILED"
exit "$fail"
