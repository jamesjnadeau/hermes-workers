# default:alpine — the Alpine sibling of Nous's Hermes sandbox base (nikolaik/python-nodejs),
# with the sandbox's CLI tools, pn user + sudo, and system Chromium for browser work
# (Playwright's own browsers and the Python playwright wheel don't run on musl; use Node
# Playwright with CHROME_PATH). No desktop / computer-use. Plus gh, Rust and the same
# extras as default:debian. No GitHub credentials are configured here; see dev:alpine.
FROM nikolaik/python-nodejs:python3.13-nodejs26-alpine

USER root

# CLI tools mirroring the Nous sandbox, plus gh and scripting/research extras.
RUN set -eux; \
    apk add --no-cache \
      bash sudo jq ripgrep fd tmux less nano vim zip unzip rsync tree procps htop file \
      util-linux ca-certificates musl-locales git openssh-client curl \
      github-cli sqlite pandoc-cli poppler-utils yq-go shellcheck make cmake build-base

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

# Python / Node tooling the Debian sandbox has.
ENV POETRY_HOME=/usr/local
RUN pip install --no-cache-dir -U pip pipenv uv "pillow>=10"; \
    curl -fsSL https://install.python-poetry.org | python3 -; \
    npm install -g corepack; \
    corepack enable yarn

# Browser: system Chromium driven by Node Playwright.
ENV CHROME_PATH=/usr/bin/chromium \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 \
    NODE_PATH=/usr/local/lib/node_modules \
    XDG_RUNTIME_DIR=/tmp/hermes-runtime \
    LANG=C.UTF-8
RUN apk add --no-cache chromium nss freetype harfbuzz ttf-dejavu font-noto; \
    npm install -g playwright@1

# pn user (1000:1000, from the base) gets bash and passwordless sudo, like the Nous sandbox.
# Its home lives in /var/lib/pn, not /home: Hermes mounts an empty root-owned tmpfs over
# /home, so as uid 1000 a home under /home can't be created (uv, npm, Chromium all fail).
# /home/pn stays as a link for plain `docker run`.
RUN id pn >/dev/null 2>&1 || { addgroup -g 1000 pn; adduser -D -u 1000 -G pn -h /home/pn pn; }; \
    mkdir -p /var/lib/pn; \
    cp -a /home/pn/. /var/lib/pn/ 2>/dev/null || true; \
    chown -R 1000:1000 /var/lib/pn; \
    rm -rf /home/pn; \
    ln -s /var/lib/pn /home/pn; \
    sed -i 's#^pn:\(.*\):/home/pn:/bin/sh$#pn:\1:/var/lib/pn:/bin/bash#' /etc/passwd; \
    echo "pn ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/pn; \
    chmod 0440 /etc/sudoers.d/pn

# Rust, system-wide but owned by pn so cargo install / rustup target add work as uid 1000.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-musl/rustup-init -o /tmp/rustup-init; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain stable -c rustfmt,clippy; \
    rm /tmp/rustup-init; \
    chown -R 1000:1000 /usr/local/rustup /usr/local/cargo; \
    rustc --version

CMD ["sleep", "infinity"]
