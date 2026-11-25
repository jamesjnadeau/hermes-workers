# Adding an image

Every image is a folder, `images/<image>/<distro>/`, holding a plain `Dockerfile` and a
`test.sh`. `docker-bake.hcl` says what each image is built on and what it's tagged as. The
example below adds a `go` image on top of `dev`.

## 1. Copy a folder

```bash
mkdir -p images/go
cp -r images/dev/debian images/go/debian
```

## 2. Edit the Dockerfile

Start from `FROM parent`. The bake file decides what `parent` is, so the Dockerfile never
names a registry or tag.

```dockerfile
# go:debian — dev:debian + Go.
FROM parent

USER root

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends golang; \
    rm -rf /var/lib/apt/lists/*
```

Keep these intact:
- don't add an `ENTRYPOINT`, and don't change `CMD` (Hermes needs `sleep infinity`);
- don't switch away from root at the end (the parents run as root, and Hermes picks the user);
- install anything uid 1000 must write to as owned by `1000:1000`;
- **never** pass a token as a build `ARG` or `ENV`. Secrets come from the Hermes profile at runtime.

## 3. Write `test.sh`

Run the parent's checks first, then add yours:

```bash
#!/usr/bin/env bash
# Smoke test for go:debian.
. /tests/lib.sh
. /images/dev/debian/test.sh --no-finish

need go
run "go builds a program" sh -c 'd=$(mktemp -d) && cd "$d" && printf "package main\nfunc main(){}\n" > m.go && go build m.go'

_maybe_finish "$@"
```

The helpers in `tests/lib.sh` are:
- `need cmd...` fails if a command is not on PATH;
- `run "description" cmd...` fails if the command exits non-zero and shows its output;
- `_maybe_finish "$@"` prints the summary. It skips this when a child image sources your test with `--no-finish`.

## 4. Add a bake target

In `docker-bake.hcl`:

```hcl
target "go-debian" {
  inherits = ["_common"]
  context  = "images/go/debian"
  contexts = { parent = "target:dev-debian" }
  tags     = tags("go", "debian")
}
```

Add `"go-debian"` to both `group "publish"` (so CI pushes it) and `group "ci"` (so CI builds
it). If the image contains software whose license forbids redistributing it, leave it out of
`publish`, give it a tag without the registry, and follow the `playdate-debian` pattern.

## 5. Add it to CI's test loop

In `.github/workflows/build.yml`, add `go-debian` to the `for t in ...` list in the **Test**
step.

## 6. Build and test locally

```bash
docker buildx bake --load go-debian
scripts/test-image.sh go-debian
```

Then open a pull request. CI builds and tests it without pushing. Merging to `main` publishes
`ghcr.io/jamesjnadeau/hermes-workers/go:debian`. Remember the one-time step of making the new
package public.

## Variants

- **An Alpine variant:** do the same in `images/go/alpine/` with `apk add`, build on
  `target:dev-alpine` and tag it `tags("go", "alpine")`. Copy rather than share: Alpine and
  Debian package names differ often enough that one shared Dockerfile gets messy.
- **A new base that isn't built on one of ours:** use a normal `FROM some/image:tag` and leave
  out `contexts`. It still needs `CMD ["sleep","infinity"]`, a `pn` user (1000:1000) whose home is
  outside `/home` (Hermes covers `/home` with an empty temporary folder; see `default/alpine`),
  and bash, because the test runner calls `bash`.
