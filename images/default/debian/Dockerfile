# default:debian — Nous's Hermes sandbox (desktop, Playwright, pn user) + gh, Rust and
# scripting/research tools. No GitHub credentials are configured here; see dev:debian.
FROM nousresearch/hermes-sandbox:desktop

USER root

# GitHub CLI (official apt repo) + extra tools.
RUN set -eux; \
    mkdir -p -m 755 /etc/apt/keyrings; \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg; \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list; \
    apt-get -o Acquire::Retries=3 update; \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
      gh sqlite3 pandoc poppler-utils shellcheck make cmake; \
    rm -rf /var/lib/apt/lists/*; \
    command -v fd >/dev/null || ln -s /usr/bin/fdfind /usr/local/bin/fd

# mikefarah yq (Debian's `yq` package is a different tool).
ARG YQ_VERSION=v4.54.3
RUN set -eux; \
    cd /tmp; \
    base="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}"; \
    curl -fsSLO "$base/yq_linux_amd64"; \
    curl -fsSLO "$base/checksums"; \
    curl -fsSLO "$base/checksums_hashes_order"; \
    col=$(( $(grep -n '^SHA-256$' checksums_hashes_order | cut -d: -f1) + 1 )); \
    echo "$(grep '^yq_linux_amd64 ' checksums | awk -v c="$col" '{print $c}')  yq_linux_amd64" | sha256sum -c -; \
    install -m 755 yq_linux_amd64 /usr/local/bin/yq; \
    rm -f yq_linux_amd64 checksums checksums_hashes_order

# Rust, system-wide but owned by pn (uid 1000) so cargo install / rustup target add work
# when Hermes runs the container as the host user.
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN set -eux; \
    curl -fsSL https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu/rustup-init -o /tmp/rustup-init; \
    chmod +x /tmp/rustup-init; \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain stable -c rustfmt,clippy; \
    rm /tmp/rustup-init; \
    chown -R 1000:1000 /usr/local/rustup /usr/local/cargo; \
    rustc --version

# Hermes mounts an empty root-owned tmpfs over /home (and /root), so as uid 1000 the
# default HOME=/home/pn doesn't exist and can't be created: uv, npm, git --global and
# Chromium all fail. Move pn's home out of /home; keep /home/pn as a link for plain
# `docker run`.
RUN usermod -d /var/lib/pn -m pn; \
    ln -s /var/lib/pn /home/pn
