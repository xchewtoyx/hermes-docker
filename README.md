# hermes-docker — containerized Hermes Agent instance

Derived image on top of the official `nousresearch/hermes-agent` distribution:
adds `curl` + `jq` for the instance's cron scripts. GitHub Actions builds it on
every push and publishes to **ghcr.io/xchewtoyx/hermes-docker** (and to Docker Hub
once `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` secrets are set).

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

## Layout

- `Dockerfile` — the derived image (ARG BASE_IMAGE to pin the upstream tag/digest)
- `docker-compose.yml` — supervised gateway + dashboard, data at `~/.hermes:/opt/data`
- `hermes.env` — runtime knobs (PUID/PGID, TZ, dashboard auth) — **not secrets for the agent**
- `MIGRATION.md` — the brain-transfer playbook from the old coder-workspace instance

Agent API keys live in the mounted `~/.hermes/.env` (never in this repo).
