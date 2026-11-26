# hermes-workers

Docker images for [Hermes Agent](https://hermes-agent.nousresearch.com/) to run its tools in.
Each Hermes profile picks one with `terminal.docker_image`, so an agent gets the toolchain its
job needs. GitHub Actions builds them, tests them and publishes them to GHCR every week.

## Images

| Image | Built on | Adds | Published |
|---|---|---|---|
| `ghcr.io/jamesjnadeau/hermes-workers/default:debian` | `nousresearch/hermes-sandbox:desktop` | gh, Rust (rustup stable + rustfmt, clippy), sqlite3, pandoc, poppler-utils, mikefarah yq, shellcheck, make, cmake | yes |
| `ghcr.io/jamesjnadeau/hermes-workers/default:alpine` | `nikolaik/python-nodejs:python3.13-nodejs26-alpine` | the Nous sandbox's CLI tools, `pn` user + sudo, uv/pipenv/poetry/yarn, Pillow, system Chromium + Node Playwright, and the same extras as `default:debian` | yes |
| `ghcr.io/jamesjnadeau/hermes-workers/dev:debian` | `default:debian` | git authenticates to GitHub through `gh`, using a token from the environment | yes |
| `ghcr.io/jamesjnadeau/hermes-workers/dev:alpine` | `default:alpine` | same as `dev:debian` | yes |
| `hermes-workers/playdate:debian` | `dev:debian` | Playdate SDK, `gcc-arm-none-eabi` + newlib, WebKitGTK for the simulator | **no, local build only** ([why](#playdate)) |

All images share these traits:
- user `pn` (1000:1000), home `/var/lib/pn` (see below), `CMD ["sleep","infinity"]` and no entrypoint;
- passwordless sudo for `pn`, which only works outside Hermes: Hermes starts workers with `no-new-privileges`, so `sudo` always fails inside a Hermes session. Install what you need in the image;
- `XDG_RUNTIME_DIR=/tmp/hermes-runtime`;
- Rust in `/usr/local/rustup` and `/usr/local/cargo`, owned by uid 1000, so `cargo install` works when Hermes runs the container as your user;
- no credentials baked in (CI checks for this).

The Debian images keep everything from the Nous sandbox: the VNC/xfce desktop, `cua-driver` and Playwright Chromium in `/opt/playwright`.

**Why `pn`'s home is `/var/lib/pn`:** Hermes mounts an empty, root-owned temporary folder over
`/home` and `/root`. In a profile with `docker_run_as_host_user: true`, the agent runs as uid
1000, so a home under `/home` can't be created, and uv, npm, `git config --global` and Chromium
all fail. With the home in `/var/lib/pn` they work. `/home/pn` links there for plain `docker run`.

Each push gets three tags:
- `:<distro>`, which moves on every build;
- `:<distro>-YYYYMMDD`, for rolling back;
- `:<distro>-<short sha>`, for rolling back.

The images are built for `linux/amd64` only. Sizes: Debian about 4 GB, Alpine about 3.2 GB, playdate about 5.3 GB.

## Using an image from a Hermes profile

In `hermes/profiles/<name>/config.yaml` (or the root `config.yaml`):

```yaml
terminal:
  backend: docker
  docker_image: ghcr.io/jamesjnadeau/hermes-workers/default:debian
```

For a profile that should work on GitHub, use a `dev` image and forward the token and git identity:

```yaml
terminal:
  backend: docker
  docker_image: ghcr.io/jamesjnadeau/hermes-workers/dev:debian
  docker_forward_env:
    - GITHUB_TOKEN
    - GIT_AUTHOR_NAME
    - GIT_AUTHOR_EMAIL
    - GIT_COMMITTER_NAME
    - GIT_COMMITTER_EMAIL
```

`gh` reads `GITHUB_TOKEN` (or `GH_TOKEN`), and git uses `gh` as its credential helper for
`https://github.com` and `https://gist.github.com`. **Profiles on a `default` image must not
forward `GITHUB_TOKEN`.** The image doesn't grant GitHub access; the profile does.

### Pulling and updating

```bash
docker pull ghcr.io/jamesjnadeau/hermes-workers/dev:debian
```

The floating tags move weekly. Re-pull on the host to pick up a new build. Containers Hermes
has already started keep the old image until they're recreated. To roll back, point
`docker_image` at a dated tag.

Hermes pulls a missing image itself through the docker socket proxy, so a profile can point
at an image the host doesn't have yet. This was verified on 2026-11-26 with `default:alpine`.
It only pulls when the image is **missing**, so use `docker pull` to refresh a floating tag the
host already has.

### One-time setup after the first publish

GHCR creates new packages as private. After CI's first push, open each package (`default`,
`dev`) under github.com/jamesjnadeau?tab=packages → Package settings → Change visibility →
Public. Then the host can pull without `docker login`.

## Alpine notes

- Alpine has no desktop or computer-use layer. Use Debian for that.
- Playwright's bundled browsers and the Python `playwright` wheel are glibc-only and don't work on Alpine.
- The Alpine images ship Alpine's own Chromium at `/usr/bin/chromium` (`CHROME_PATH`) and a global Node `playwright`. Launch Playwright with `executablePath: process.env.CHROME_PATH` and `--no-sandbox`.
- That Chromium is for scripts the agent writes and runs in the worker. **Hermes's own browser tool doesn't use the worker** unless Hermes's Bot Desktop is placed in the sandbox, and that needs the Debian desktop layer. Otherwise the tool runs Chromium on the Hermes side: the configured cloud browser (in this setup, Browser Use through the Nous tool gateway) or a local Chromium in the Hermes container. Verified on 2026-11-26: a profile on `default:alpine` browsed fine with `browser_exec`. Don't set `browser.executable_path` to `/usr/bin/chromium`. That setting is for the Hermes-side Chromium, and the path doesn't exist there.
- Use Debian if you want the agent's browser visible on the sandbox desktop (Bot Desktop), or Playwright from Python.

## Playdate

Panic's [SDK license](https://play.date/dev/sdk-license/) (section 2) forbids distributing the
SDK, so `playdate:debian` is never pushed anywhere. Build it on the Hermes host. It downloads the
SDK from Panic and uses the published `dev:debian` as its parent:

```bash
docker buildx bake --load playdate-debian
scripts/test-image.sh playdate-debian
```

The result is `hermes-workers/playdate:debian`, with the SDK in `/opt/playdate-sdk`
(`PLAYDATE_SDK_PATH`) and `pdc`, `pdutil` and `PlaydateSimulator` on PATH. Re-run the build to
pick up a newer SDK, but skip the layer cache and pull a fresh parent first, or Docker reuses
the old SDK layer:

```bash
docker pull ghcr.io/jamesjnadeau/hermes-workers/dev:debian
docker buildx bake --load --no-cache playdate-debian
```

`--set playdate-debian.args.PLAYDATE_SDK_URL=...` pins a specific SDK version. The simulator can run on the inherited VNC desktop. The SDK's `setup.sh` (udev rules,
icons) isn't run, so a USB-connected Playdate isn't set up. If the build fails to fetch
`dev:debian`, the package is still private. Make it public (see above) or `docker login ghcr.io`.

CI builds this image with `INSTALL_SDK=0` and tests it without the SDK, so the Dockerfile keeps
working.

## Building and testing locally

```bash
docker buildx bake --load publish                  # all published images
docker buildx bake --load dev-alpine               # one image (builds its parents too)
scripts/test-image.sh dev-alpine                   # test it
```

`scripts/test-image.sh` checks that the image keeps `sleep infinity` as its command, has no
entrypoint and contains no tokens in its env, labels, build history or config files. It then
runs the image's `test.sh` four ways:
- as root;
- as uid 1000 with an unfamiliar `HOME`;
- with Hermes's own docker flags (capabilities dropped, `no-new-privileges`, temporary folders over `/tmp`, `/run`, `/home` and `/root`) in a login shell, as root;
- the same Hermes flags and login shell, as uid 1000.

The login shell matters because Hermes takes its environment from `bash -l`, and `/etc/profile`
resets `PATH`. The images put Rust and the Playdate SDK back on `PATH` with `/etc/profile.d` scripts.

## Adding an image

See [docs/adding-an-image.md](docs/adding-an-image.md).
