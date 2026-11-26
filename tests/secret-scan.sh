#!/usr/bin/env bash
# Regression test for the "no secrets" check in scripts/test-image.sh: each probe image must be flagged by the "no secrets" check; the clean one must not.
cd "$(dirname "$0")/.."
base=ghcr.io/jamesjnadeau/hermes-workers/default:alpine
mkdir -p images/probe/alpine && printf '#!/usr/bin/env bash\n. /tests/lib.sh\nfinish\n' > images/probe/alpine/test.sh
rc=0
probe() { # name expect(flag|clean) dockerfile-lines
  local name=$1 expect=$2; shift 2
  printf 'FROM %s\n%s\n' "$base" "$*" | docker build -q -t ghcr.io/jamesjnadeau/hermes-workers/probe:alpine - >/dev/null
  if scripts/test-image.sh probe-alpine 2>&1 | grep -q 'FAIL  possible secrets'; then got=flag; else got=clean; fi
  [ "$got" = "$expect" ] && echo "ok    $name ($got)" || { echo "WRONG $name: expected $expect, got $got"; rc=1; }
}
probe actions-token flag 'ENV CI_THING=ghs_abcdefghijklmnopqrstuvwxyz0123456789'
probe gist-pat      flag 'ARG GIST_PAT=abc123
RUN echo built'
probe api-key       flag 'ENV OPENAI_API_KEY=sk-live-123'
probe url-creds     flag 'ENV MIRROR=https://user:hunter2@example.com/repo'
probe file-token    flag 'RUN echo "ghp_abcdefghijklmnopqrstuvwxyz0123456789" > /etc/leak'
probe file-only    flag 'RUN printf "gh%s_%s" p abcdefghijklmnopqrstuvwxyz0123456789 > /etc/leak2'
probe token-url     clean 'ENV TOKEN_URL=https://example.com/oauth'
probe plain         clean 'ENV FOO=bar'
rm -rf images/probe; docker rmi -f ghcr.io/jamesjnadeau/hermes-workers/probe:alpine >/dev/null
exit $rc
