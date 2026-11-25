# hermes-workers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A repo that builds, tests and publishes layered Hermes worker images (default, dev on Debian + Alpine; playdate on Debian, local-only) with docs for adding more.

**Architecture:** One plain Dockerfile per `images/<image>/<distro>/`, each with a `test.sh` beside it. `docker-bake.hcl` wires parents through a named build context `parent`, so `docker buildx bake` builds in dependency order locally and in GitHub Actions. CI builds, runs every `test.sh` (as root and as uid 1000), then pushes to GHCR — except playdate, which is never pushed.

**Tech Stack:** Docker Buildx Bake (HCL), Bash, GitHub Actions, GHCR.

**Spec:** `docs/superpowers/specs/2026-11-25-hermes-workers-design.md`

## Global Constraints

- Registry prefix: `ghcr.io/jamesjnadeau/hermes-workers`; image refs `<prefix>/<image>:<distro>`, plus `<distro>-YYYYMMDD` and `<distro>-<short sha>`.
- Platform: `linux/amd64` only.
- Debian default base: `nousresearch/hermes-sandbox:desktop`. Alpine default base: `nikolaik/python-nodejs:python3.13-nodejs26-alpine`.
- Every image keeps: user `pn` 1000:1000 with NOPASSWD sudo, `CMD ["sleep","infinity"]`, no `ENTRYPOINT`, `XDG_RUNTIME_DIR=/tmp/hermes-runtime`; Debian also keeps `PLAYWRIGHT_BROWSERS_PATH=/opt/playwright` and the desktop layer.
- No secret in any layer, ENV, ARG default or label. GitHub access only via runtime env (`GITHUB_TOKEN`/`GH_TOKEN`).
- Rust: rustup stable, `RUSTUP_HOME=/usr/local/rustup`, `CARGO_HOME=/usr/local/cargo`, `/usr/local/cargo/bin` on PATH, both dirs owned `1000:1000`.
- `yq` is mikefarah yq on both distros (`yq --version` contains `mikefarah`).
- Playdate SDK is never pushed anywhere (Panic SDK license §2). SDK URL: `https://download.panic.com/playdate_sdk/Linux/PlaydateSDK-latest.tar.gz`.
- Out of scope: any change to `arr-stack` profiles or its `hermes-sandbox/` build.
- Dockerfiles stay copy-friendly: no shared templates, no generated files.

## Review Focus

1. **Run as uid 1000 with a HOME that doesn't exist or isn't `/home/pn`** (Hermes `docker_run_as_host_user` + `home_mode: auto` sets HOME to a mounted dir) → every tool still runs and Rust/cargo dirs are writable. Pinned by the runner's second pass (`--user 1000:1000 -e HOME=/tmp/hermes-home`), Task 1.
2. **An upstream base changes under the weekly rebuild** (Nous drops `pn`, renames a tool, changes CMD) → the run fails before anything is pushed. Pinned by CI ordering (test before push), Task 5, plus `check_image_contract` in Task 1.
3. **A token leaks into an image** (someone adds `ARG GITHUB_TOKEN` or bakes `gh auth login`) → build fails. Pinned by `check_no_secrets` in `scripts/test-image.sh`, Task 1, applied to every image.
4. **Hermes starts the container with its own command as non-root** → no ENTRYPOINT that needs root, CMD stays `sleep infinity`. Pinned by `check_image_contract`, Task 1.
5. **Playdate built locally before `dev:debian` is public / pulled** → bake pulls the parent itself via `docker-image://`; if the package is still private the README's error note applies. Pinned by the README step in Task 4 and the manual local-build verification in Task 4.

---

## File Structure

```
docker-bake.hcl                     all targets, tags, parent wiring, groups
scripts/test-image.sh               runs one target's test.sh in the built image (root + uid 1000) + host-side checks
tests/lib.sh                        helpers sourced inside containers: need, need_version, pass/fail summary
images/default/debian/{Dockerfile,test.sh}
images/default/alpine/{Dockerfile,test.sh}
images/dev/debian/{Dockerfile,test.sh}
images/dev/alpine/{Dockerfile,test.sh}
images/playdate/debian/{Dockerfile,test.sh}
.github/workflows/build.yml
README.md
docs/adding-an-image.md
```

---

### Task 1: Test harness, bake skeleton, default/debian

**Files:**
- Create: `tests/lib.sh`, `scripts/test-image.sh`, `docker-bake.hcl`, `images/default/debian/Dockerfile`, `images/default/debian/test.sh`

**Interfaces:**
- Produces:
  - `tests/lib.sh` (sourced, bash): `need <cmd>...` (fail if not on PATH), `run <desc> <cmd...>` (fail with desc if cmd non-zero), `finish` (print summary, exit 1 if any failure). Failures accumulate; the script doesn't stop at the first one.
  - `scripts/test-image.sh <target>` where target is `<image>-<distro>`; the image ref under test is `${REGISTRY}/<image>:<distro>` with `REGISTRY` defaulting to `ghcr.io/jamesjnadeau/hermes-workers`. It mounts `images/` at `/images:ro` and `tests/` at `/tests:ro`, runs `bash /images/<image>/<distro>/test.sh` twice: as default user, then `--user 1000:1000 -e HOME=/tmp/hermes-home`. Before that it runs host-side `check_image_contract` (docker inspect: `.Config.Cmd == ["sleep","infinity"]`, `.Config.Entrypoint` null/empty) and `check_no_secrets` (no env/ARG/label key or value matching `(?i)(token|secret|password|ghp_|github_pat_)` in `docker inspect` + `docker history --no-trunc`, except the allowlisted `GPG_KEY` env from the Python base). Exit non-zero on any failure.
  - Test-script convention: each `test.sh` starts `. /tests/lib.sh`, may source its parent's test with `. /images/<parent>/<distro>/test.sh --no-finish`, and ends with `finish` unless passed `--no-finish`.
  - `docker-bake.hcl`: `variable "REGISTRY"` (default `ghcr.io/jamesjnadeau/hermes-workers`), `variable "DATE"` (default `""`), `variable "SHA"` (default `""`), `function "tags"(image, distro)` returning the floating tag plus `-${DATE}` / `-${SHA}` tags only when those are non-empty; target `_common` with `platforms = ["linux/amd64"]`; target `default-debian` (`context = "images/default/debian"`).

- [ ] **Step 1: Write `tests/lib.sh` and `images/default/debian/test.sh`**

`test.sh` checks (all must pass as root and as uid 1000):
```bash
need python3 pip uv node npm yarn git gh cargo rustc rustup jq rg fd tmux rsync zip sqlite3 pandoc pdftotext yq shellcheck make cmake sudo
run "yq is mikefarah"        sh -c 'yq --version | grep -q mikefarah'
run "python is 3.13"         sh -c 'python3 -c "import sys; assert sys.version_info[:2]==(3,13)"'
run "pillow imports"         python3 -c "import PIL"
run "cargo home writable"    test -w /usr/local/cargo -a -w /usr/local/cargo/bin -a -w /usr/local/rustup
run "rust compiles"          sh -c 'd=$(mktemp -d) && cd "$d" && cargo init -q --name t && cargo build -q --offline'
run "pn user is 1000"        sh -c '[ "$(id -u pn)" = 1000 ]'
run "pn has nopasswd sudo"   sh -c 'sudo -n -u pn sudo -n true'   # as uid 1000 this is plain `sudo -n true`; branch on id -u
run "XDG_RUNTIME_DIR set"    test "$XDG_RUNTIME_DIR" = /tmp/hermes-runtime
run "playwright browsers"    test "$PLAYWRIGHT_BROWSERS_PATH" = /opt/playwright
run "chromium headless"      sh -c 'c=$(ls -d /opt/playwright/chromium-*/chrome-linux*/chrome | head -1); "$c" --headless --no-sandbox --disable-gpu --dump-dom "data:text/html,<title>ok</title>" | grep -q "<title>ok</title>"'
run "no github token"        test -z "${GITHUB_TOKEN:-}${GH_TOKEN:-}"
finish
```
(`cargo init` needs no network; if `--offline` errors on an empty dep set, drop the flag. Make the sudo check `if [ "$(id -u)" = 0 ]; then su pn -c 'sudo -n true'; else sudo -n true; fi`.)

- [ ] **Step 2: Write `scripts/test-image.sh` and the bake skeleton with `default-debian` pointing at a Dockerfile that is just `FROM nousresearch/hermes-sandbox:desktop`**

- [ ] **Step 3: Run to verify it fails**

Run: `docker buildx bake --load default-debian && scripts/test-image.sh default-debian`
Expected: FAIL listing missing `gh cargo rustc rustup sqlite3 pandoc pdftotext yq shellcheck cmake fd` and the cargo checks; contract and secrets checks PASS.

- [ ] **Step 4: Write `images/default/debian/Dockerfile`**

`FROM nousresearch/hermes-sandbox:desktop`, `USER root`. Layers, in order (one RUN each so they cache separately):
1. apt: `gh` from cli.github.com repo (same method as `arr-stack/hermes-sandbox/Dockerfile`), `sqlite3 pandoc poppler-utils shellcheck make cmake`; `ln -s /usr/bin/fdfind /usr/local/bin/fd` if `fd` absent.
2. yq: `ARG YQ_VERSION=v4.48.1` (implementer: use current latest v4 at build time and pin it), download `yq_linux_amd64` from mikefarah/yq releases to `/usr/local/bin/yq`, verify with the release `checksums` file.
3. Rust: `ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH`; `rustup-init -y --no-modify-path --profile minimal --default-toolchain stable -c rustfmt,clippy`; `chown -R 1000:1000 /usr/local/rustup /usr/local/cargo`.
Do not set USER (keep upstream's default), CMD or ENTRYPOINT.

- [ ] **Step 5: Run to verify it passes**

Run: `docker buildx bake --load default-debian && scripts/test-image.sh default-debian`
Expected: both passes print all PASS, exit 0.

- [ ] **Step 6: Commit**

```bash
git add tests scripts docker-bake.hcl images/default/debian
git commit -m "Add test harness, bake file and default:debian image"
```

---

### Task 2: default/alpine

**Files:**
- Create: `images/default/alpine/Dockerfile`, `images/default/alpine/test.sh`
- Modify: `docker-bake.hcl` (add `default-alpine`)

**Interfaces:**
- Consumes: `tests/lib.sh`, `scripts/test-image.sh`, `tags()` from Task 1.
- Produces: target `default-alpine` → `${REGISTRY}/default:alpine`. Env contract on Alpine: `CHROME_PATH=/usr/bin/chromium`, `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`, `NODE_PATH=/usr/local/lib/node_modules`.

- [ ] **Step 1: Write `images/default/alpine/test.sh`**

Same checks as Debian's test.sh with these differences (copy the file, don't source it — distros diverge):
- drop the `PLAYWRIGHT_BROWSERS_PATH` and `/opt/playwright` chromium checks; add:
```bash
need bash chromium
run "chromium headless"   sh -c 'chromium --headless --no-sandbox --disable-gpu --dump-dom "data:text/html,<title>ok</title>" | grep -q "<title>ok</title>"'
run "node playwright drives system chromium" node -e '
  const { chromium } = require("playwright");
  (async () => { const b = await chromium.launch({ executablePath: process.env.CHROME_PATH, args:["--no-sandbox"] });
    const p = await b.newPage(); await p.setContent("<title>ok</title>");
    if (await p.title() !== "ok") process.exit(1); await b.close(); })().catch(e => { console.error(e); process.exit(1); });'
run "default shell for pn is bash" sh -c 'getent passwd pn | grep -q ":/bin/bash$"'
```

- [ ] **Step 2: Add `default-alpine` to bake with a Dockerfile that is just the nikolaik base; run to verify it fails**

Run: `docker buildx bake --load default-alpine && scripts/test-image.sh default-alpine`
Expected: FAIL listing missing tools, chromium, playwright; contract checks PASS.

- [ ] **Step 3: Write `images/default/alpine/Dockerfile`**

`FROM nikolaik/python-nodejs:python3.13-nodejs26-alpine`, `USER root`, `SHELL ["/bin/bash","-euo","pipefail","-c"]` after bash is installed. Layers:
1. apk: `bash sudo jq ripgrep fd tmux less nano vim zip unzip rsync tree procps htop file util-linux ca-certificates musl-locales git openssh-client curl github-cli sqlite pandoc-cli poppler-utils yq-go shellcheck make cmake build-base` (implementer: fix any name that doesn't exist in the base's Alpine release; `yq-go` must yield mikefarah yq).
2. Python: `pip install --no-cache-dir -U pip pipenv uv "pillow>=10"` and poetry via install.python-poetry.org with `POETRY_HOME=/usr/local` (skip any the base already has); `corepack enable yarn`.
3. Browser: apk `chromium nss freetype harfbuzz ttf-dejavu font-noto`; `npm install -g playwright@1`; `ENV CHROME_PATH=/usr/bin/chromium PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 NODE_PATH=/usr/local/lib/node_modules XDG_RUNTIME_DIR=/tmp/hermes-runtime LANG=C.UTF-8`.
4. User: create group/user `pn` 1000:1000 with `/bin/bash` and home `/home/pn` if the base lacks it (else `usermod`/edit shell to bash); `/etc/sudoers.d/pn` = `pn ALL=(ALL) NOPASSWD:ALL`, mode 0440.
5. Rust: same ENV and rustup steps as Debian (rustup-init for `x86_64-unknown-linux-musl`), same chown.
6. `CMD ["sleep","infinity"]`.

- [ ] **Step 4: Run to verify it passes**

Run: `docker buildx bake --load default-alpine && scripts/test-image.sh default-alpine`
Expected: all PASS both passes.

- [ ] **Step 5: Commit**

```bash
git add images/default/alpine docker-bake.hcl
git commit -m "Add default:alpine image"
```

---

### Task 3: dev/debian and dev/alpine

**Files:**
- Create: `images/dev/{debian,alpine}/{Dockerfile,test.sh}`
- Modify: `docker-bake.hcl` (add `dev-debian`, `dev-alpine` with `contexts = { parent = "target:default-<distro>" }`; group `publish` = the four default/dev targets)

**Interfaces:**
- Consumes: targets `default-debian`, `default-alpine`; test convention `--no-finish`.
- Produces: `${REGISTRY}/dev:debian`, `${REGISTRY}/dev:alpine`; bake group `publish`.

- [ ] **Step 1: Write both `test.sh`**

```bash
. /tests/lib.sh
. /images/default/<distro>/test.sh --no-finish
run "gh credential helper for github.com" sh -c '[ "$(git config --system --get credential.https://github.com.helper)" = "!gh auth git-credential" ]'
run "gist helper too" sh -c '[ "$(git config --system --get credential.https://gist.github.com.helper)" = "!gh auth git-credential" ]'
run "gh picks up GITHUB_TOKEN" sh -c 'GITHUB_TOKEN=dummy gh auth status 2>&1 | grep -q GITHUB_TOKEN'
finish
```
(The last check needs network only to fail auth; if the runner has no network make it `GITHUB_TOKEN=dummy gh auth token | grep -q dummy`. Prefer the `auth token` form — it's offline.)

- [ ] **Step 2: Add bake targets with Dockerfiles that are only `FROM parent`; run to verify they fail**

Run: `docker buildx bake --load dev-debian dev-alpine && scripts/test-image.sh dev-debian && scripts/test-image.sh dev-alpine`
Expected: default checks PASS, credential-helper checks FAIL.

- [ ] **Step 3: Write both Dockerfiles**

`FROM parent`, `USER root`, `RUN git config --system credential.https://github.com.helper '' && git config --system --add credential.https://github.com.helper '!gh auth git-credential'` and the same for `https://gist.github.com`. Then restore the parent's user: Debian — no USER line needed if the parent left the default; if Task 1's Dockerfile ended as root, keep root (match upstream `nousresearch/hermes-sandbox:desktop`'s `.Config.User`, which is empty). Add a comment block at the top: the token comes from the profile's `docker_forward_env: [GITHUB_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME, GIT_COMMITTER_EMAIL]`.

- [ ] **Step 4: Run to verify they pass**

Same command as Step 2. Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add images/dev docker-bake.hcl
git commit -m "Add dev images with gh credential helper"
```

---

### Task 4: playdate/debian (local-only)

**Files:**
- Create: `images/playdate/debian/{Dockerfile,test.sh}`
- Modify: `docker-bake.hcl`

**Interfaces:**
- Consumes: `dev-debian`.
- Produces: bake `variable "PLAYDATE_PARENT"` (default `docker-image://ghcr.io/jamesjnadeau/hermes-workers/dev:debian`), `variable "INSTALL_SDK"` (default `"1"`); target `playdate-debian` with `contexts = { parent = PLAYDATE_PARENT }`, `args = { INSTALL_SDK = INSTALL_SDK }`, `tags = ["hermes-workers/playdate:debian"]` (local name, no registry — never pushable to GHCR by accident). Not in group `publish`. Group `ci` = `publish` + `playdate-debian`. `scripts/test-image.sh` maps target `playdate-debian` to ref `hermes-workers/playdate:debian`.

- [ ] **Step 1: Write `test.sh`**

```bash
. /tests/lib.sh
. /images/dev/debian/test.sh --no-finish
need arm-none-eabi-gcc cmake
run "newlib present" sh -c 'echo "int main(){return 0;}" | arm-none-eabi-gcc -x c --specs=nosys.specs -o /tmp/a.elf -'
if [ "${EXPECT_SDK:-1}" = 1 ]; then
  need pdc
  run "PLAYDATE_SDK_PATH set" test -d "$PLAYDATE_SDK_PATH/C_API"
  run "pdc compiles a Lua game" sh -c 'd=$(mktemp -d); mkdir "$d/src"; echo "import \"CoreLibs/graphics\"; function playdate.update() end" > "$d/src/main.lua"; pdc "$d/src" "$d/out.pdx" && test -f "$d/out.pdx/main.pdz"'
fi
finish
```
`scripts/test-image.sh` passes `-e EXPECT_SDK` through when set.

- [ ] **Step 2: Add the target with Dockerfile `FROM parent`; run to verify it fails**

Run: `docker buildx bake --load --set playdate-debian.contexts.parent=target:dev-debian playdate-debian && scripts/test-image.sh playdate-debian`
Expected: FAIL on `arm-none-eabi-gcc`, `pdc`.

- [ ] **Step 3: Write the Dockerfile**

`FROM parent`, `USER root`, `ARG INSTALL_SDK=1`, `ARG PLAYDATE_SDK_URL=https://download.panic.com/playdate_sdk/Linux/PlaydateSDK-latest.tar.gz`. Top-of-file comment: SDK license forbids redistribution; this image is built locally only, never pushed.
1. apt: `gcc-arm-none-eabi libnewlib-arm-none-eabi cmake` plus the simulator's runtime libs listed in the SDK's `setup.sh` (install them directly rather than running setup.sh, which needs a TTY/udev).
2. `if [ "$INSTALL_SDK" = 1 ]; then` download, extract to `/opt/playdate-sdk` (strip the versioned top dir), `chown -R 1000:1000 /opt/playdate-sdk`; `fi`.
3. `ENV PLAYDATE_SDK_PATH=/opt/playdate-sdk PATH=/opt/playdate-sdk/bin:$PATH`.

- [ ] **Step 4: Run to verify it passes, with and without SDK**

Run: `docker buildx bake --load --set playdate-debian.contexts.parent=target:dev-debian playdate-debian && scripts/test-image.sh playdate-debian`
Expected: all PASS.
Run: `docker buildx bake --load --set playdate-debian.contexts.parent=target:dev-debian --set playdate-debian.args.INSTALL_SDK=0 playdate-debian && EXPECT_SDK=0 scripts/test-image.sh playdate-debian`
Expected: all PASS, no pdc checks run.

- [ ] **Step 5: Commit**

```bash
git add images/playdate docker-bake.hcl scripts/test-image.sh
git commit -m "Add local-only playdate:debian image"
```

---

### Task 5: GitHub Actions workflow

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: bake groups `publish`, `ci`; variables `REGISTRY`, `DATE`, `SHA`, `PLAYDATE_PARENT`, `INSTALL_SDK`; `scripts/test-image.sh`.

- [ ] **Step 1: Write the workflow**

- `on`: `push` (branches `[main]`), `pull_request`, `schedule` (`cron: "17 6 * * 1"`), `workflow_dispatch`.
- `permissions: { contents: read, packages: write }`; `concurrency: build-${{ github.ref }}`, cancel-in-progress.
- One job, `ubuntu-latest`:
  1. checkout; free disk space (remove `/usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL`, `docker system prune -af`) — the Debian images are ~4 GB each.
  2. `docker/setup-buildx-action` (pin a current major).
  3. Env: `DATE=$(date -u +%Y%m%d)`, `SHA=${GITHUB_SHA::7}`, `PLAYDATE_PARENT=target:dev-debian`, `INSTALL_SDK=0`.
  4. `docker buildx bake --load ci` with `--set *.cache-from=type=gha --set *.cache-to=type=gha,mode=max` (`docker/bake-action` acceptable instead).
  5. Test: `for t in default-debian default-alpine dev-debian dev-alpine; do scripts/test-image.sh "$t"; done; EXPECT_SDK=0 scripts/test-image.sh playdate-debian`.
  6. If `github.event_name != 'pull_request'`: `docker/login-action` to `ghcr.io` with `${{ github.actor }}` / `${{ secrets.GITHUB_TOKEN }}`, then push every tag of the `publish` targets only (`docker buildx bake --print publish | jq -r '.target[].tags[]' | xargs -n1 docker push`).

- [ ] **Step 2: Lint**

Run: `docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:latest -color` and `docker buildx bake --print ci >/dev/null`
Expected: no actionlint findings; bake prints valid JSON.

- [ ] **Step 3: Verify the push list excludes playdate**

Run: `docker buildx bake --print publish | jq -r '.target[].tags[]'`
Expected: exactly 4 refs (no DATE/SHA set locally), none containing `playdate`.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "Add CI: build, test, publish to GHCR"
```

(First real run happens after James pushes; see Task 6 Step 3.)

---

### Task 6: Docs, push, verify in CI

**Files:**
- Create: `README.md`, `docs/adding-an-image.md`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Write `README.md`**

Sections: what this repo is; table of images (ref, base, what's in it, published?); using an image from a Hermes profile (the YAML from the spec, the dev `docker_forward_env` list, "default profiles must not forward GITHUB_TOKEN"); pulling/refreshing (`docker pull <ref>` on the host; floating tags move weekly; dated tags for rollback; whether Hermes auto-pulls — from Step 4); one-time step: set each GHCR package to public after first push (Package settings → Change visibility); Alpine notes (system Chromium at `/usr/bin/chromium`, set Hermes `browser` `executable_path` to it, Python Playwright wheel doesn't work on musl — use Node Playwright; Debian recommended for browsing-heavy profiles; no desktop/computer-use); Playdate (license reason, local build: `docker buildx bake playdate-debian`, result `hermes-workers/playdate:debian`, re-run to pick up a new SDK, private-package error note); building/testing locally (`docker buildx bake --load <target> && scripts/test-image.sh <target>`).

- [ ] **Step 2: Write `docs/adding-an-image.md`**

Walk through adding a hypothetical `go` image on top of `dev`: copy `images/dev/debian` → `images/go/debian`, edit Dockerfile (`FROM parent` + one RUN), write `test.sh` sourcing the parent's with `--no-finish`, add a bake target (show the exact 6-line HCL block with `inherits = ["_common"]`, `contexts`, `tags = tags("go","debian")`), add it to group `publish` (or not, if it holds licensed software — point to playdate), add a line to CI's test loop, build + test locally, open a PR. Also: adding an Alpine variant, and a new top-level base (no `contexts`).

- [ ] **Step 3: Ask James to push, then watch the first run**

Pushing to GitHub is outward-facing: ask James for the go-ahead, then `git push -u origin main`. Check the Actions run; fix failures until green. Then ask James to flip the four packages to public.

- [ ] **Step 4: Verify from the Hermes host**

Run: `docker pull ghcr.io/jamesjnadeau/hermes-workers/default:alpine` (after packages are public) and `docker run --rm ghcr.io/jamesjnadeau/hermes-workers/dev:debian gh --version`.
Expected: pulls without login; prints gh version.
Then: with James's OK, check whether Hermes's browser tool works against `default:alpine` (temporary profile in `arr-stack/hermes/profiles/`, removed afterwards) and whether Hermes pulls a missing image itself through the socket proxy. Record both results in the README. If James declines, the README says "not yet verified".

- [ ] **Step 5: Commit**

```bash
git add README.md docs/adding-an-image.md
git commit -m "Add README and guide for adding images"
```
