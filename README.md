# hermes-docker — containerized Hermes Agent images

Two images derived from the official `nousresearch/hermes-agent` distribution:

| Image | Purpose |
| --- | --- |
| `ghcr.io/xchewtoyx/hermes-docker` | Headless Hermes plus shared developer tooling |
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
# Edit hermes.env: set dashboard basic-auth password/secret and your timezone.
docker compose pull
docker compose run --rm hermes setup
docker compose up -d
```

This is a greenfield-first deployment. Compose creates a persistent
`hermes-data` named volume, and the upstream image seeds its standard
`config.yaml`, `.env`, and `SOUL.md` when that volume is empty. The setup command
then configures providers and other user choices in that volume. Recreating or
upgrading the container does not remove it.

Run `docker compose run --rm hermes setup` before the first `up -d`; it finalizes
the freshly seeded configuration using the current Hermes schema.

Do not run `docker compose down -v` unless you intentionally want to delete the
Hermes state volume and start over.

The repo is public, so the image pulls anonymously — no login needed on the new host:

```bash
docker pull ghcr.io/xchewtoyx/hermes-docker:latest
```

## Existing installation / migration

Only use the migration overlay when intentionally attaching an existing host
Hermes home and repositories:

```bash
docker compose \
  -f docker-compose.yml \
  -f docker-compose.migration.yml \
  up -d
```

For the GUI image, include `docker-compose.gui.yml` before the migration
overlay. Set `PUID` and `PGID` in `hermes.env` to the owner of the bind-mounted
directories. See [MIGRATION.md](MIGRATION.md) for the complete transplant flow.

## Container path contract

The canonical state root inside the container is always `$HERMES_HOME`
(`/opt/data`), whether it is backed by the default named volume or the optional
host bind mount. Inside the image, resolve Hermes files from that variable—for
example, `$HERMES_HOME/config.yaml`—rather than assuming
`~/.hermes/config.yaml`.

`HOME` is intentionally different between process classes:

| Context | `HOME` | Purpose |
| --- | --- | --- |
| Gateway, dashboard, and GUI services | `/opt/data` | Hermes service runtime |
| Agent tool subprocesses | `/opt/data/home` | Persistent, isolated Git/CLI configuration |
| Raw `docker exec` as root | `/root` | Operator shell; the `hermes` shim drops privileges and resets `HOME` |

Both derived images install `/etc/profile.d/hermes-path.sh`. This restores
`/opt/hermes/bin`, `/opt/hermes/.venv/bin`, and `/opt/data/.local/bin` after
Debian's `/etc/profile` resets `PATH`, so `hermes` remains available in nested
login shells such as `bash -lc`.

## Developer tools

Both images inherit one `devtools` stage from `Dockerfile`, allowing Docker
Build Cloud to reuse the same layers across the `headless` and `gui` targets.
The layer explicitly provides:

- `uv` and `uvx` 0.12.6, copied from Astral's pinned multi-architecture image
- `gh` 2.98.0, installed from GitHub's immutable release archives with
  architecture-specific SHA-256 verification
- `curl`, `jq`, and CA certificates

The upstream Hermes image currently also supplies Git, OpenSSH, ripgrep,
Make, GCC/G++, Node/npm, and Python. Those inherited tools are useful but are
not pinned by this project.

GitHub authentication is instance state, not image content. Agent subprocesses
use `/opt/data/home` as `HOME`, so authenticate that persistent home explicitly:

```bash
docker exec --user hermes -e HOME=/opt/data/home -it hermes gh auth login
```

Do not add GitHub tokens or `hosts.yml` to either image.

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

The Cua Driver version is pinned by `CUA_DRIVER_VERSION` in the `gui` target of
`Dockerfile` and can be overridden with a build argument. Cua telemetry and
background update checks are disabled in the immutable image; upgrades arrive
through a rebuilt container image.

## Layout

- `Dockerfile` — shared `devtools` stage plus `headless` and `gui` targets
- `docker-compose.yml` — greenfield deployment with a Docker-managed state volume
- `docker-compose.gui.yml` — overlay selecting the GUI image and local noVNC port
- `docker-compose.migration.yml` — optional existing-state and repository bind mounts
- `docker/common/hermes-path.sh` — preserves Hermes CLI paths in login shells
- `docker/gui/` — GUI session runner and s6 service wiring
- `hermes.env` — runtime knobs (PUID/PGID, TZ, dashboard auth) — **not secrets for the agent**
- `MIGRATION.md` — the brain-transfer playbook from the old coder-workspace instance

Agent API keys live at `$HERMES_HOME/.env` in the persistent volume (never in
this repo).
