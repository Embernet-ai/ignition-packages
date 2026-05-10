# syntax=docker/dockerfile:1.7
#
# Embernet Ignition Edge 8.3.6 (Linux ARM64) — containerized.
#
# Wraps Inductive Automation's portable ZIP install tree (the same files
# you'd extract by running their official Linux ZIP installer) into a
# debian:bookworm-slim base. The ZIP bundles its own JRE in jre-tmp/, so
# we don't need to install Java in the base — just glibc + libfontconfig
# (Ignition's UI render layer).
#
# We use a multi-stage build so the 1.85 GB ZIP and the curl/unzip tools
# don't end up in the final image. The unpacker stage downloads + extracts;
# the runtime stage gets only /opt/ignition COPY'd in.
#
# Built with:
#   podman build --platform linux/arm64 \
#     --build-arg IGNITION_VERSION=8.3.6 \
#     -t ghcr.io/embernet-ai/ignition-edge:8.3.6 \
#     -f Containerfile .

ARG IGNITION_VERSION=8.3.6

# ─── Stage 1: download + unpack the ZIP ──────────────────────────────────────
FROM debian:bookworm-slim AS unpacker

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG IGNITION_VERSION

WORKDIR /tmp
RUN curl -fSL --retry 3 --retry-delay 5 \
      -o ig.zip \
      "https://github.com/Embernet-ai/ignition-packages/releases/download/v${IGNITION_VERSION}/Ignition-Edge-linux-aarch-64-${IGNITION_VERSION}.zip" \
 && mkdir -p /opt/ignition \
 && unzip -q ig.zip -d /opt/ignition \
 && rm -f ig.zip \
 && chmod +x /opt/ignition/ignition.sh \
             /opt/ignition/gwcmd.sh \
             /opt/ignition/ignition-secrets-tool.sh \
             /opt/ignition/ignition-gateway 2>/dev/null || true

# ─── Stage 2: runtime image ──────────────────────────────────────────────────
FROM debian:bookworm-slim

ARG IGNITION_VERSION

LABEL org.opencontainers.image.title="Embernet Ignition Edge ${IGNITION_VERSION} (ARM64)"
LABEL org.opencontainers.image.description="Inductive Automation Ignition Edge ${IGNITION_VERSION} packaged for ARM64 deployment via Quadlet on EmberNet edge appliances. Modules pre-loaded; demo mode by default."
LABEL org.opencontainers.image.vendor="Fireball Industries"
LABEL org.opencontainers.image.source="https://github.com/Embernet-ai/ignition-packages"
LABEL ignition.version="${IGNITION_VERSION}"
LABEL ignition.edition="edge"

# Minimal runtime deps — Ignition's bundled JRE handles the rest.
# libfontconfig1 + fontconfig-config: Ignition Designer/Vision render layer.
# tzdata: stable timezone resolution.
# bash + procps: ignition.sh + wrapper rely on them.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libfontconfig1 fontconfig-config \
      tzdata bash procps tini \
 && rm -rf /var/lib/apt/lists/*

# Bring in the unpacked install tree from the unpacker stage.
COPY --from=unpacker /opt/ignition /usr/local/bin/ignition

WORKDIR /usr/local/bin/ignition

# Ports:
#   8088/tcp - Gateway HTTP (web UI)
#   8043/tcp - Gateway HTTPS
#   8060/udp - Gateway Network (GAN — multi-gateway federation)
EXPOSE 8088/tcp 8043/tcp 8060/udp

# Demo mode: no license auto-applied. Operator activates via web UI on
# first boot. EULA pre-accepted via env so the gateway boots unattended.
# Admin user/password applied on first boot via gwcmd.sh during init below.
ENV ACCEPT_IGNITION_EULA=Y \
    IGNITION_EDITION=edge \
    GATEWAY_ADMIN_USERNAME=admin \
    GATEWAY_ADMIN_PASSWORD=embernet \
    GATEWAY_HTTP_PORT=8088 \
    GATEWAY_HTTPS_PORT=8043 \
    GATEWAY_GAN_PORT=8060 \
    DISABLE_QUICKSTART=true \
    LANG=C.UTF-8

# ignition.sh is the official control script. It backgrounds the gateway
# (via the wrapper) and exits. We need a foreground process to keep the
# container alive — exec tail -F on the wrapper log. tini reaps zombies
# from the wrapper so we don't accumulate defunct procs across restarts.
ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "-c"]
CMD ["set -e; \
      cd /usr/local/bin/ignition; \
      ./ignition.sh start; \
      sleep 8; \
      mkdir -p logs; \
      touch logs/wrapper.log; \
      exec tail -F logs/wrapper.log"]
