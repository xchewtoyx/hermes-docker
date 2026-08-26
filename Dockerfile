# Hermes Agent images built from one shared developer-tools stage.
#
# Targets:
#   headless (default) — Hermes plus general diagnostics/development tooling
#   gui                — headless tooling plus XFCE, Chromium, and Cua Driver
ARG BASE_IMAGE=nousresearch/hermes-agent:latest
ARG UV_IMAGE=ghcr.io/astral-sh/uv:0.12.6@sha256:88bc6eb1ccd4b82efd0e1b530caffabddf50dc2bf612e66c14ea25b8ee8a4d3d

FROM ${UV_IMAGE} AS uv

FROM ${BASE_IMAGE} AS devtools

USER root

# Keep the shared layer small. Git, SSH, ripgrep, build-essential, Node/npm,
# and Python are already provided by the upstream Hermes distribution.
RUN apt-get -o Acquire::Retries=3 update \
 && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
      ca-certificates \
      curl \
      jq \
 && rm -rf /var/lib/apt/lists/*

# Pin uv/uvx from Astral's signed multi-arch distroless image. This deliberately
# replaces the versions inherited from the moving Hermes base image.
COPY --from=uv /uv /uvx /usr/local/bin/

# GitHub CLI publishes immutable releases. Verify the archive selected for the
# BuildKit target architecture before installing the single Go binary.
ARG TARGETARCH
ARG GH_VERSION=2.98.0
ARG GH_AMD64_SHA256=3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de
ARG GH_ARM64_SHA256=cf689084f3a3618f7eae4a2420d335d74626d65f5e594b9828d125d69f800d86
RUN case "${TARGETARCH}" in \
      amd64) gh_sha256="${GH_AMD64_SHA256}" ;; \
      arm64) gh_sha256="${GH_ARM64_SHA256}" ;; \
      *) echo "Unsupported TARGETARCH for gh: ${TARGETARCH}" >&2; exit 2 ;; \
    esac \
 && gh_archive="gh_${GH_VERSION}_linux_${TARGETARCH}.tar.gz" \
 && curl -fsSL --retry 3 --retry-all-errors \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${gh_archive}" \
      -o "/tmp/${gh_archive}" \
 && printf '%s  %s\n' "${gh_sha256}" "/tmp/${gh_archive}" | sha256sum -c - \
 && tar -xzf "/tmp/${gh_archive}" -C /tmp \
 && install -m 0755 \
      "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}/bin/gh" \
      /usr/local/bin/gh \
 && rm -rf "/tmp/${gh_archive}" "/tmp/gh_${GH_VERSION}_linux_${TARGETARCH}" \
 && uv --version \
 && uvx --version \
 && gh --version

# Debian's /etc/profile resets PATH in `bash -lc`; restore the baked Hermes
# paths for operator login shells as well as ordinary supervised processes.
COPY --chmod=0644 docker/common/hermes-path.sh /etc/profile.d/hermes-path.sh


FROM devtools AS gui

# X11 desktop, Chromium, accessibility bridge, and a loopback-published noVNC
# viewer. Runtime processes are dropped back to the base image's hermes user by
# the s6 service below.
RUN apt-get -o Acquire::Retries=3 update \
 && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
      at-spi2-core \
      chromium \
      dbus-x11 \
      libglib2.0-bin \
      libxi6 \
      novnc \
      websockify \
      x11-utils \
      x11vnc \
      xvfb \
      xfce4 \
      xfce4-terminal \
 && rm -rf /var/lib/apt/lists/*

# Pin the downloaded driver even though the installer itself tracks the current
# install protocol. Override at build time with --build-arg CUA_DRIVER_VERSION=…
ARG CUA_DRIVER_VERSION=0.22.1
RUN curl -fsSL --retry 3 --retry-all-errors \
      https://cua.ai/driver/install.sh \
      -o /tmp/install-cua-driver.sh \
 && CUA_DRIVER_RS_VERSION="${CUA_DRIVER_VERSION}" \
      CUA_DRIVER_RS_HOME=/opt/cua-driver \
      CUA_DRIVER_RS_INSTALL_DIR=/usr/local/bin \
      CUA_DRIVER_RS_NO_MODIFY_PATH=1 \
      CUA_DRIVER_RS_TELEMETRY_ENABLED=false \
      bash /tmp/install-cua-driver.sh --no-modify-path \
 && rm /tmp/install-cua-driver.sh \
 && chmod -R a+rX /opt/cua-driver \
 && cua-driver --version

# These values must be visible to Hermes and any cua-driver process it spawns,
# not just to the sibling GUI service.
ENV DISPLAY=:99 \
    XDG_SESSION_TYPE=x11 \
    XDG_RUNTIME_DIR=/tmp/hermes-runtime \
    DBUS_SESSION_BUS_ADDRESS=unix:path=/tmp/hermes-session-bus \
    NO_AT_BRIDGE=0 \
    CUA_DRIVER_RS_TELEMETRY_ENABLED=false \
    CUA_DRIVER_RS_UPDATE_CHECK=false

COPY --chmod=0755 docker/gui/hermes-gui /usr/local/bin/hermes-gui
COPY --chmod=0755 docker/gui/cont-init.d/03-hermes-gui-setup \
    /etc/cont-init.d/03-hermes-gui-setup
COPY --chmod=0755 docker/gui/s6-rc.d/ /etc/s6-overlay/s6-rc.d/

# VNC stays internal. Only noVNC is intended for host publication, bound to
# host loopback by docker-compose.gui.yml.
EXPOSE 6080


# Keep headless as the final stage so `docker build .` retains its historical
# behavior. Cloud builds select both targets explicitly.
FROM devtools AS headless
