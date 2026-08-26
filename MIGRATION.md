# Migrating the Hermes instance from the coder workspace into Docker

Target: dedicated container running the official `nousresearch/hermes-agent` image
(derived image adds curl/jq), with s6-overlay supervising gateway + dashboard + cron.

Total to move: ~30 MB of brain state + ~217 MB of `~/repos`. The 2 GB `hermes-agent/`
source tree, `bin/`, and `lsp/` stay behind — the image has its own immutable install
at `/opt/hermes`.

## What the "brain" is — copied vs left behind

COPY (everything stateful):
`config.yaml` `.env` `auth.json` `SOUL.md` `memories/` `skills/` `cron/` (jobs.json +
executions.db + output/) `state.db*` `kanban.db*` `response_store.db*`
`verification_evidence.db` `sessions/` `scripts/` `hooks/` `shared/` `state/`
`platforms/` `sandboxes/` `pairing/` `pending_messages/` `terminal-sessions/`
`channel_directory.json` `gateway_state.json` `spawn-ledger.json`
`hermes-sa.json` `slack-manifest.json` `.hermes_history`

LEAVE BEHIND (regenerable or image-owned):
`hermes-agent/` (2 GB git source — NOT the container's install) `bin/` `lsp/`
`cache/` `audio_cache/` `image_cache/` `logs/` `models_dev_cache*`
`provider_models_cache.json` `ollama_cloud_models_cache.json` `processes.json`
`gateway.pid` `gateway-starts.log` `*.lock` `.curator_backups/`
`.skills_prompt_snapshot.json` `.update_check`

## Phase 0 — snapshot (optional, cheap insurance)

    hermes backup -o ~/hermes-backup-$(date +%Y%m%d).zip

## Phase 1 — stop the old instance cleanly

The old gateway must be down before the container starts (never run two gateways
against the same data dir — session/memory stores are not concurrency-safe).

    hermes gateway stop          # stops the host gateway (PID was 185202)
    pkill -f 'hermes serve'      # stop the 9119 backend (PID was 173493)

Confirm: `ps aux | grep -E 'hermes (gateway|serve)'` → nothing.

## Phase 2 — copy the brain to the new host

    rsync -avz --progress \
      --exclude 'hermes-agent/' --exclude 'bin/' --exclude 'lsp/' \
      --exclude 'cache/' --exclude 'audio_cache/' --exclude 'image_cache/' \
      --exclude 'logs/' --exclude '*.lock' --exclude 'gateway.pid' \
      --exclude 'gateway-starts.log' --exclude 'processes.json' \
      --exclude 'models_dev_cache*' --exclude 'provider_models_cache.json' \
      --exclude 'ollama_cloud_models_cache.json' --exclude '.update_check' \
      --exclude '.skills_prompt_snapshot.json' --exclude '.curator_backups/' \
      ~/.hermes/  newhost:~/.hermes/

    rsync -avz ~/repos/ newhost:~/repos/        # OKF wikis + rgh-botnet

Then on the new host: `chown -R $(id -u):$(id -g) ~/.hermes` and set `PUID` /
`PGID` in `hermes.env` to that owning user. The baseline Compose file uses a
greenfield named volume; this migration uses `docker-compose.migration.yml` to
replace it with these host bind mounts.

## Phase 3 — path adjustments (the only edits needed)

1. Seed the container's tool-subprocess HOME so git/gh work inside the container:

       mkdir -p ~/.hermes/home/.config/gh
       cp ~/.gitconfig ~/.hermes/home/.gitconfig
       cp ~/.config/gh/hosts.yml ~/.hermes/home/.config/gh/hosts.yml

   Then edit `~/.hermes/home/.gitconfig`: the old box's credential helper is an
   absolute path (`!/usr/local/bin/gh auth git-credential`). Change both helpers to
   `helper = !gh auth git-credential` (PATH-resolved) or verify `which gh` inside the
   container and keep the absolute form.

2. Point the botnet heartbeat at the container's repos mount:

       sed -i 's|/home/coder/repos/rgh-botnet|/opt/repos/rgh-botnet|' \
         ~/.hermes/scripts/botnet-heartbeat.sh

3. Make the okf-wikis skill's `~/repos/*` paths resolve (tool subprocess HOME is
   `/opt/data/home`):

       mkdir -p ~/.hermes/home
       ln -s /opt/repos ~/.hermes/home/repos

4. `GOOGLE_CHAT_SERVICE_ACCOUNT_JSON=hermes-sa.json` is a relative path — resolves
   against HERMES_HOME, so it works unchanged (`hermes-sa.json` rides along in the copy).

5. Recreate the OKF CLI venv with the container's Python (ABI-safe) once the image
   is built:

       docker compose \
         -f docker-compose.yml \
         -f docker-compose.migration.yml \
         run --rm hermes bash -lc '
         python3 -m venv /opt/data/home/.venvs/okf && \
         /opt/data/home/.venvs/okf/bin/pip install --quiet okf-core \
           --index-url https://xchewtoyx.github.io/okf-core/simple/ && \
         /opt/data/home/.venvs/okf/bin/okf --version'

6. Audit copied host scripts for container path and platform assumptions:

   - Resolve Hermes state from `${HERMES_HOME:-$HOME/.hermes}` rather than a
     literal `$HOME/.hermes`; agent tool subprocesses use `HOME=/opt/data/home`.
   - Use GNU/Linux command syntax in the Debian image—for example,
     `stat -c %Y FILE` rather than macOS `stat -f %m FILE`.

## Phase 4 — bring it up

    docker compose \
      -f docker-compose.yml \
      -f docker-compose.migration.yml \
      pull
    docker compose \
      -f docker-compose.yml \
      -f docker-compose.migration.yml \
      up -d
    docker compose logs -f hermes          # watch gateway boot + Slack connect

For the GUI/computer-use image, select the Compose overlay instead:

    docker compose \
      -f docker-compose.yml \
      -f docker-compose.gui.yml \
      -f docker-compose.migration.yml \
      pull
    docker compose \
      -f docker-compose.yml \
      -f docker-compose.gui.yml \
      -f docker-compose.migration.yml \
      up -d

The noVNC viewer is then available on `http://127.0.0.1:6080/vnc.html`; use an
SSH tunnel when the Docker host is remote rather than publishing it publicly.

(`docker compose build` is only needed when iterating on the Dockerfile locally —
the image normally comes from ghcr.io, built by CI.)

Verification checklist:

    docker exec hermes /opt/hermes/bin/hermes -p default gateway status   # "Manager: s6 (container supervisor)"
    docker exec hermes /command/s6-svstat /run/service/gateway-default
    docker exec hermes /opt/hermes/bin/hermes doctor
    docker exec hermes /opt/hermes/bin/hermes cron status # scheduler lives inside the gateway
    docker exec hermes bash -lc 'command -v hermes'        # login-shell PATH survives /etc/profile
    curl -s http://localhost:8642/v1/models -H "Authorization: Bearer $API_SERVER_KEY"
    # dashboard: http://<new-host>:9119  → basic-auth login
    # Slack: DM the bot — it must reply
    # Only if Nous Portal OAuth broke (auth.json should carry it): docker exec hermes /opt/hermes/bin/hermes setup --portal

Recommended for an unattended gateway (docs guidance):

    docker exec hermes /opt/hermes/bin/hermes config set tool_loop_guardrails.hard_stop_enabled true

## Phase 5 — cutover notes

- Test on the SAME box before decommissioning? Copy the data to `~/.hermes-test`
  first and run a second container (`container_name: hermes-test`, `-p 9642:8642`)
  against it — never against the live `~/.hermes` while the old gateway is up.
- Version jump: this box runs v0.20.5 (128 commits behind); the image ships its own
  release. config.yaml (v38) auto-migrates on first boot and will write a
  `config.yaml.bak` like it already has once. The single carried local commit
  (chore: author-map merge of PR #92529) is git-metadata only — safe to drop.
- Upgrades from now on: repeat the migration-overlay `pull` and `up -d`
  commands above (`hermes update` does not apply inside the immutable image).
- Rollback: the old box keeps its data untouched until you decommission it.
