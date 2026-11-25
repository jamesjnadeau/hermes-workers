#!/usr/bin/env bash
# Smoke test for dev:debian — everything default:debian has, plus gh-backed git credentials.
. /tests/lib.sh
. /images/default/debian/test.sh --no-finish

run "gh credential helper for github.com" sh -c '[ "$(git config --system --get credential.https://github.com.helper)" = "!gh auth git-credential" ]'
run "gh credential helper for gist"      sh -c '[ "$(git config --system --get credential.https://gist.github.com.helper)" = "!gh auth git-credential" ]'
run "gh picks up GITHUB_TOKEN from env"  sh -c 'GITHUB_TOKEN=dummy gh auth token 2>/dev/null | grep -qx dummy'

_maybe_finish "$@"
