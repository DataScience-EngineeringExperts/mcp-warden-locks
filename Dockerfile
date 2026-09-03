# Attester image: node 22 + python 3.11 + mcp-warden (capture only; signing happens
# on the host). Built fresh on every run from a digest-pinned base; nothing from a
# target package is ever baked in.
ARG NODE_BASE=node:22-bookworm-slim@sha256:83f487e0a63425e5b4d146fb5e5be574bcbe1b7b843d3ebafdd95eaf7767a7e5
FROM ${NODE_BASE}
ARG WARDEN_REF=main
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-venv python3-pip git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN python3 -m venv /opt/warden \
 && /opt/warden/bin/pip install --no-cache-dir --upgrade pip \
 && /opt/warden/bin/pip install --no-cache-dir "mcp-warden-cli @ git+https://github.com/DataScience-EngineeringExperts/mcp-warden@${WARDEN_REF}"
ENV PATH=/opt/warden/bin:/usr/local/bin:/usr/bin:/bin
ENTRYPOINT []
