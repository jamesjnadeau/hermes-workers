# playdate:debian — dev:debian + Playdate SDK and the ARM toolchain for C games.
#
# LOCAL BUILD ONLY. Panic's SDK license (section 2) forbids distributing the SDK, so this
# image is never pushed to a registry. Build it on the Hermes host:
#   docker buildx bake --load playdate-debian
# CI builds it with INSTALL_SDK=0 so the Dockerfile is tested without the SDK.
FROM parent

USER root

# ARM toolchain for C games + the libraries PlaydateSimulator links against.
# The simulator can run on the inherited VNC desktop.
RUN set -eux; \
    apt-get -o Acquire::Retries=3 update; \
    apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
      gcc-arm-none-eabi libnewlib-arm-none-eabi cmake libwebkit2gtk-4.1-0; \
    rm -rf /var/lib/apt/lists/*

ARG INSTALL_SDK=1
ARG PLAYDATE_SDK_URL=https://download.panic.com/playdate_sdk/Linux/PlaydateSDK-latest.tar.gz
RUN set -eux; \
    if [ "$INSTALL_SDK" = 1 ]; then \
      mkdir -p /opt/playdate-sdk; \
      curl -fsSL "$PLAYDATE_SDK_URL" | tar xz -C /opt/playdate-sdk --strip-components=1; \
      chown -R 1000:1000 /opt/playdate-sdk; \
      cat /opt/playdate-sdk/VERSION.txt; \
    fi

ENV PLAYDATE_SDK_PATH=/opt/playdate-sdk \
    PATH=/opt/playdate-sdk/bin:$PATH

# Login shells (Hermes snapshots `bash -l`) reset PATH in /etc/profile; put the SDK back.
RUN printf '%s\n' 'case ":$PATH:" in *:/opt/playdate-sdk/bin:*) ;; *) PATH=/opt/playdate-sdk/bin:$PATH ;; esac' 'export PATH' > /etc/profile.d/hermes-workers-playdate.sh
