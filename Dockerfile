# Derived Hermes Agent image — official distribution + this instance's extra tooling.
# Built & published by GitHub Actions to ghcr.io (and optionally Docker Hub).
#
# The base image is stateless and already ships s6-overlay process supervision
# (gateway + dashboard + per-profile slots, auto-restart, rotated logs).
# This layer only adds the CLI tools this instance's cron scripts need.
ARG BASE_IMAGE=nousresearch/hermes-agent:latest
FROM ${BASE_IMAGE}

# deepseek-balance.sh uses curl + python3; jq for JSON parsing.
# git/gh/ssh ship in the base image (used by tool subprocesses under /opt/data/home).
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl jq \
 && rm -rf /var/lib/apt/lists/*
