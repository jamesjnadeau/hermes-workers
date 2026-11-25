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
- user `pn` (1000:1000) with passwordless sudo, `CMD ["sleep","infinity"]` and no entrypoint;
- `XDG_RUNTIME_DIR=/tmp/hermes-runtime`;
- Rust in `/usr/local/rustup` and `/usr/local/cargo`, owned by uid 1000, so `cargo install` works when Hermes runs the container as your user;
- no credentials baked in (CI checks for this).

The Debian images keep everything from the Nous sandbox: the VNC/xfce desktop, `cua-driver` and Playwright Chromium in `/opt/playwright`.

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

Whether Hermes pulls a missing image itself through the docker socket proxy is **not yet
verified**. Until it is, pull new images on the host before switching a profile to them.

### One-time setup after the first publish

GHCR creates new packages as private. After CI's first push, open each package (`default`,
`dev`) under github.com/jamesjnadeau?tab=packages → Package settings → Change visibility →
Public. Then the host can pull without `docker login`.

## Alpine notes

- Alpine has no desktop or computer-use layer. Use Debian for that.
- Playwright's bundled browsers and the Python `playwright` wheel are glibc-only and don't work on Alpine.
- The Alpine images ship Alpine's own Chromium at `/usr/bin/chromium` (`CHROME_PATH`) and a global Node `playwright`. Launch Playwright with `executablePath: process.env.CHROME_PATH` and `--no-sandbox`.
- For Hermes's own browser tool, set the `browser` `executable_path` to `/usr/bin/chromium`. Whether that tool works against an Alpine worker is **not yet verified**.
- Use Debian for profiles that do a lot of browsing.

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
pick up a newer SDK (`--set playdate-debian.args.PLAYDATE_SDK_URL=...` pins a specific
version). The simulator can run on the inherited VNC desktop. The SDK's `setup.sh` (udev rules,
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
entrypoint and contains no tokens. It then runs the image's `test.sh` twice: as root, and as
uid 1000 with an unfamiliar `HOME`, the way Hermes runs it.

## Adding an image

See [docs/adding-an-image.md](docs/adding-an-image.md).
