# hermes-workers — design

Date: 2026-11-25
Repo: https://github.com/jamesjnadeau/hermes-workers (public, empty at time of writing)

## Intent

James runs Hermes Agent (Nous Research) in his `arr-stack` compose project. Hermes runs agent
tool commands in a sibling Docker container chosen per profile via `terminal.docker_image`
(in `arr-stack/hermes/config.yaml` and `arr-stack/hermes/profiles/<name>/config.yaml`). Today
the only custom image is `arr-hermes-sandbox:latest`, built locally from
`arr-stack/hermes-sandbox/Dockerfile` (= `nousresearch/hermes-sandbox:desktop` + `gh`).

He wants a dedicated repo that builds a family of worker images in CI and publishes them to a
registry, so each Hermes profile can point at the image with the right toolchain for its job,
and so adding a new worker is quick and obvious. Agent work in these images is mainly **coding,
scripting and research**.

## Goals

- Images, layered:
  - **default** — `debian` and `alpine` variants. Python, Node, Rust, `gh`, common CLI tools,
    browser automation. No GitHub access configured.
  - **dev** — built on default, `debian` and `alpine` variants. Configured to use a GitHub
    token supplied at runtime.
  - **playdate** — built on dev, **debian only**. Adds the Playdate SDK.
- Automated build + test + publish in GitHub Actions.
- Same build command works locally.
- Clear written instructions for adding another image (copy a folder, add a few lines).

## Non-goals

- Baking any secret into an image. GitHub access is granted by the Hermes profile at runtime
  (`terminal.docker_forward_env`), never at build time.
- A desktop / computer-use environment on Alpine.
- arm64 images (host is x86_64; Playdate Linux SDK is x86_64).
- Using unofficial community `*/hermes-sandbox` images from Docker Hub as bases.

## Anti-goals (would be failure even if it "works")

- Debian images that lose Hermes features the stock sandbox has (browser tool via Playwright,
  desktop/VNC, `pn` uid-1000 user with passwordless sudo, `/opt/playwright`, `XDG_RUNTIME_DIR`).
- Dockerfiles so clever (shared ARG-switched templates, generated files) that copying one to
  start a new image is hard.
- A token or credential ending up in a published layer.

## Constraints and facts found

- Stock sandbox `nousresearch/hermes-sandbox:desktop` (~3 GB) is Debian trixie, built from
  `nikolaik/python-nodejs` (Python 3.13, Node 26, pip/pipenv/uv/poetry, yarn via corepack),
  then adds: `jq ripgrep fd-find tmux less nano vim-tiny zip rsync tree procps htop file
  bsdextrautils ca-certificates locales sudo`; a VNC + xfce desktop; Playwright Chromium in
  `/opt/playwright`; `cua-driver`; Pillow; user `pn` (1000:1000) with NOPASSWD sudo;
  env `PLAYWRIGHT_BROWSERS_PATH=/opt/playwright`, `XDG_RUNTIME_DIR=/tmp/hermes-runtime`;
  `CMD ["sleep","infinity"]`. Versioned tags exist (e.g. `v0.23.4-desktop`) plus floating `desktop`.
- `nikolaik/python-nodejs:python3.13-nodejs26-alpine` exists — the exact Alpine sibling of
  Nous's base layer. This is the Alpine starting point.
- Playwright on Alpine (musl): only Chromium works, and only the system `apk add chromium`
  build driven via `executablePath` / Hermes `browser` `executable_path`. Playwright's bundled
  browsers and the Python `playwright` pip wheel are glibc-only; Node Playwright works.
  Firefox/WebKit are not usable (they need Playwright-patched builds).
- Profiles may set `docker_run_as_host_user: true` (runs as uid 1000). Tools must work as
  uid 1000, not only as root.
- Hermes reaches Docker through `tecnativa/docker-socket-proxy` with CONTAINERS/POST/EXEC/IMAGES.

## Approaches considered

- **A. One folder per image×distro, ordered by a single `docker-bake.hcl` (chosen).** Each
  `images/<name>/<distro>/Dockerfile` is a plain Dockerfile; the bake file declares parents via
  named build contexts so `docker buildx bake` builds in dependency order, locally and in CI.
  Easy to read and copy. Chosen by James.
- B. One Dockerfile per image with a distro ARG. Fewer files but apt/apk differ on nearly every
  line; turns into conditionals, hurts copy-and-iterate.
- C. One GitHub workflow per image chained with `workflow_run`. No bake, but fragile chains and
  no local equivalent.

## Design (decided)

### Layout

```
images/
  default/debian/Dockerfile   FROM nousresearch/hermes-sandbox:desktop
  default/alpine/Dockerfile   FROM nikolaik/python-nodejs:python3.13-nodejs26-alpine
  dev/debian/Dockerfile       FROM parent  (bake context → default-debian)
  dev/alpine/Dockerfile       FROM parent  (bake context → default-alpine)
  playdate/debian/Dockerfile  FROM parent  (bake context → dev-debian)
  <each>/test.sh              smoke test run inside the built image
docker-bake.hcl
.github/workflows/build.yml
README.md                     what each image is, tags, how to use from a Hermes profile
docs/adding-an-image.md       step-by-step for a new worker
```

Child Dockerfiles use `FROM parent`; the bake target maps `contexts = { parent = "target:<x>" }`.

### Image contents

- **default/debian**: stock sandbox + `gh` (official apt repo) + Rust via rustup (stable,
  system-wide in `/usr/local/rustup` + `/usr/local/cargo`, on PATH, both owned by `pn`
  (1000:1000) so `cargo install` / `rustup target add` work under `docker_run_as_host_user`) +
  `build-essential`-level tools already present + extras for scripting/research:
  `sqlite3 pandoc poppler-utils yq shellcheck make cmake`. Keeps every stock env var, user and
  CMD.
- **default/alpine**: nikolaik Alpine base, then mimic the stock sandbox minus the desktop:
  `bash` as default shell, the same CLI tool list (Alpine package names), `sudo`, user `pn`
  1000:1000 with NOPASSWD sudo, `locales` equivalent, Pillow, uv/pipenv/poetry and yarn as in
  the base, `chromium` + fonts from apk, Node `playwright` package installed globally and
  configured to use `/usr/bin/chromium`, `XDG_RUNTIME_DIR=/tmp/hermes-runtime`,
  `CMD ["sleep","infinity"]`. Plus the same additions as default/debian (gh, Rust, extras).
- **dev/\***: `git config --system credential.helper '!gh auth git-credential'` for
  github.com, `gh` reads `GITHUB_TOKEN`/`GH_TOKEN` from env automatically. Git author identity
  comes from env (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_*`) forwarded by the
  profile. No token at build time.
- **playdate/debian**: Playdate SDK unpacked to `/opt/playdate-sdk`, `PLAYDATE_SDK_PATH` set,
  `bin/` on PATH, plus `gcc-arm-none-eabi` / `libnewlib-arm-none-eabi` and `cmake` for C games.
  Simulator can use the inherited desktop.
  **Never published.** Panic's SDK license §2 forbids distributing the SDK ("You can't
  distribute our SDK"), so (James's decision) the SDK is downloaded from
  `https://download.panic.com/playdate_sdk/Linux/PlaydateSDK-latest.tar.gz` (version
  overridable by ARG) only when the image is built **locally on James's host**, using the
  published `dev:debian` as parent. A build ARG (e.g. `INSTALL_SDK=1`, default on locally)
  lets CI build and test the Dockerfile **without** the SDK so it can't silently rot; CI never
  pushes a playdate image. Local result tagged `hermes-workers/playdate:debian`. README gives
  the one-line local build command and notes the license.

### Tags and registry

GHCR: `ghcr.io/jamesjnadeau/hermes-workers/<image>:<distro>` (floating), plus
`<distro>-YYYYMMDD` and `<distro>-<short sha>` for rollback. `linux/amd64` only.

*Builder's call:* packages are **public** (repo is public, images hold no secrets), so the host
and Hermes pull without `docker login`. GHCR creates new packages private, so the README tells
James to flip each package to public once after its first push.

### CI (`.github/workflows/build.yml`)

- Triggers: push to `main`, pull requests, weekly schedule (pick up new Nous/nikolaik/Alpine
  bases), manual dispatch.
- Steps: buildx setup → `docker buildx bake` (GHA cache) → run each image's `test.sh` →
  on non-PR runs, push all tags except playdate. PRs build and test but never push.
  Playdate is built in CI with the SDK step disabled and tested only for its non-SDK parts.
- Uses the workflow `GITHUB_TOKEN` with `packages: write`; no other secrets.

### Tests (`test.sh` per image)

Fail the build if any expected tool is missing: `python3 node npm uv cargo rustc gh git rg jq`
etc. print versions; run as uid 1000 too; Chromium launches headless (Playwright on Debian,
`chromium --headless --dump-dom` / Node Playwright on Alpine); dev checks the credential
helper is configured; playdate runs `pdc --version`.

### Using an image from Hermes

Profile config:

```yaml
terminal:
  backend: docker
  docker_image: ghcr.io/jamesjnadeau/hermes-workers/dev:debian
  docker_forward_env: [GITHUB_TOKEN, GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL]   # dev only
```

Default-image profiles must not forward `GITHUB_TOKEN`.

**Out of scope (James's decision):** switching arr-stack's Hermes profiles to these images,
removing `arr-stack/hermes-sandbox/`, and deciding where `GIST_PAT` belongs. That is a later,
separate change in arr-stack. This work ends at published images + docs.

*Builder's call (Alpine browser bar):* Alpine guarantees system Chromium headless and Node
Playwright driving `/usr/bin/chromium`; tests check both. Whether Hermes's own browser tool
works against an Alpine worker is verified during implementation and documented either way;
README recommends Debian for browsing-heavy profiles.

## Left to the builder

- Exact Alpine package names and the Pillow/build deps needed on musl.
- Whether Hermes pulls a missing image itself through the socket proxy; if not, document
  `docker pull` on the host (and how to refresh the floating tags).
- Wording and structure of README and `docs/adding-an-image.md`.
