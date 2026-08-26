# hermes-docker — containerized Hermes Agent images

Two images derived from the official `nousresearch/hermes-agent` distribution:

| Image | Purpose |
| --- | --- |
| `ghcr.io/xchewtoyx/hermes-docker` | Headless Hermes plus `curl` and `jq` for instance cron scripts |
| `ghcr.io/xchewtoyx/hermes-docker-gui` | XFCE/Xvfb desktop, Chromium, Cua Driver, and a local noVNC viewer |

Both are published as native `linux/amd64` and `linux/arm64` images, so Docker
selects the x86 Linux or Apple Silicon variant automatically. GitHub Actions
orchestrates the builds on the `xchewtoyx/clustertool` Docker Build Cloud
builder and pushes directly to GHCR (and optionally Docker Hub).

The base image already supervises the gateway, dashboard, and per-profile gateways
with **s6-overlay** (auto-restart on crash, rotated logs). Docker's
`restart: unless-stopped` is the outer safety net.

## Pull / run

```bash
git clone https://github.com/xchewtoyx/hermes-docker.git
cd hermes-docker
cp hermes.env hermes.env  # edit: PUID/PGID (host uid of ~/.hermes owner), TZ,
                          # dashboard basic-auth username/password/secret
docker compose pull
docker compose up -d
```

The repo is public, so the image pulls anonymously — no login needed on the new host:

```bash
docker pull ghcr.io/xchewtoyx/hermes-docker:latest
```

## GUI / local computer use

Use the Compose overlay to select the GUI image while retaining the volumes,
resource limits, gateway, dashboard, and healthcheck from the base Compose file:

```bash
docker compose -f docker-compose.yml -f docker-compose.gui.yml pull
docker compose -f docker-compose.yml -f docker-compose.gui.yml up -d
```

Open <http://127.0.0.1:6080/vnc.html?autoconnect=1&resize=scale>. noVNC is
passwordless but is published on host loopback only. For a remote Linux box,
keep that binding and tunnel it instead of exposing port 6080:

```bash
ssh -L 6080:127.0.0.1:6080 newhost
```

Hermes includes a native `computer_use` toolset which wraps Cua Driver; do not
also register the raw Cua MCP server. Verify the complete path after startup:

```bash
docker exec hermes /opt/hermes/bin/hermes computer-use status
docker exec hermes /opt/hermes/bin/hermes computer-use doctor
docker exec hermes /opt/hermes/bin/hermes tools list
```

If needed, enable the tool for CLI sessions and install Cua's maintained agent
guidance into the persistent Hermes data volume:

```bash
docker exec hermes /opt/hermes/bin/hermes tools enable computer_use --platform cli
docker exec --user hermes hermes cua-driver skills install
```

The desktop and Cua processes run as the non-root `hermes` user on one X11 and
D-Bus session. Xvfb does not provide `/dev/uinput`, so Cua can use AT-SPI and
foreground input normally, but non-accessible surfaces may require
`delivery_mode: foreground` rather than raw background pixel input.

GUI runtime defaults live in `hermes.env`: `GUI_SCREEN=1440x900x24` and
`ENABLE_NOVNC=1`. Set `NOVNC_HOST_PORT` or `NOVNC_BIND_ADDRESS` in the shell
running Compose to override the host-side mapping.

## Image builds

The workflow requires these repository settings:

- Variable `DOCKERHUB_USERNAME` (currently `xchewtoyx`).
- Secret `DOCKERHUB_TOKEN`, with access to Docker Build Cloud and write access
  when Docker Hub publishing is enabled.
- Optional variable `CLOUD_BUILDER_NAME`; it defaults to `clustertool`.
- Optional variable `DOCKERHUB_ENABLED=true` to publish both images to Docker
  Hub as well as GHCR.

The Cua Driver version is pinned by `CUA_DRIVER_VERSION` in `Dockerfile.gui` and
can be overridden with a build argument. Cua telemetry and background update
checks are disabled in the immutable image; upgrades arrive through a rebuilt
container image.

## Layout

- `Dockerfile` — the derived image (ARG BASE_IMAGE to pin the upstream tag/digest)
- `Dockerfile.gui` — GUI/computer-use image and pinned Cua Driver install
- `docker-compose.yml` — supervised gateway + dashboard, data at `~/.hermes:/opt/data`
- `docker-compose.gui.yml` — overlay selecting the GUI image and local noVNC port
- `docker/gui/` — GUI session runner and s6 service wiring
- `hermes.env` — runtime knobs (PUID/PGID, TZ, dashboard auth) — **not secrets for the agent**
- `MIGRATION.md` — the brain-transfer playbook from the old coder-workspace instance

Agent API keys live in the mounted `~/.hermes/.env` (never in this repo).
