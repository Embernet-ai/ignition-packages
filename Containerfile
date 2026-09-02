# syntax=docker/dockerfile:1.7
#
# Embernet Ignition Edge 8.3.8 (Linux ARM64) — containerized.
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

ARG IGNITION_VERSION=8.3.8

# ─── Stage 1: download + unpack the ZIP ──────────────────────────────────────
FROM debian:bookworm-slim AS unpacker

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      curl unzip ca-certificates \
 && rm -rf /var/lib/apt/lists/*

ARG IGNITION_VERSION
# Buildx auto-injects TARGETARCH = "arm64" or "amd64" based on --platform.
# IA's release uses the suffix "aarch-64" for ARM64 and "x86-64" for AMD64.
ARG TARGETARCH

WORKDIR /tmp
RUN set -eux; \
    case "${TARGETARCH}" in \
      arm64) IA_ARCH=aarch-64 ;; \
      amd64) IA_ARCH=x86-64 ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fSL --retry 3 --retry-delay 5 \
      -o ig.zip \
      "https://github.com/Embernet-ai/ignition-packages/releases/download/v${IGNITION_VERSION}/Ignition-Edge-linux-${IA_ARCH}-${IGNITION_VERSION}.zip"; \
    mkdir -p /opt/ignition; \
    unzip -q ig.zip -d /opt/ignition; \
    rm -f ig.zip; \
    # IA's portable ZIP ships shell scripts without the executable bit
    # (Windows-style perms preserved by unzip). ignition.sh invokes
    # ignition-util.sh as a subprocess, not via `source`, so it MUST
    # be +x or the gateway aborts with "Found ... but could not execute".
    # Recursively chmod every .sh in the install tree (some, like
    # ignition-util.sh, have a later mtime than ignition.sh and were
    # missed by a single-level glob on prior builds). Fail loudly if
    # ignition-util.sh isn't present at the expected path.
    find /opt/ignition -type f -name '*.sh' -exec chmod 755 {} +; \
    chmod 755 /opt/ignition/ignition-gateway; \
    test -x /opt/ignition/ignition-util.sh || { echo "FATAL: ignition-util.sh missing or not executable after chmod" >&2; ls -la /opt/ignition/ignition-util.sh 2>&1; exit 1; }

# ─── Stage 2: runtime image ──────────────────────────────────────────────────
FROM debian:bookworm-slim

ARG IGNITION_VERSION
ARG TARGETARCH

LABEL org.opencontainers.image.title="Embernet Ignition Edge ${IGNITION_VERSION}"
LABEL org.opencontainers.image.description="Inductive Automation Ignition Edge ${IGNITION_VERSION} packaged for multi-arch (linux/arm64 + linux/amd64) Quadlet deployment on EmberNet edge appliances and UT3 control-plane nodes. Modules pre-loaded; demo mode by default."
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

# Create the 'ignition' service user. ignition.sh drops privileges to
# this user at startup and aborts with "User ignition does not exist"
# if it's missing (cp01 bare-metal install creates it via the .run
# installer; the portable-zip Edge image gets no installer, so we
# create it ourselves here).
RUN groupadd --system --gid 999 ignition \
 && useradd --system --uid 999 --gid 999 \
      --home-dir /usr/local/bin/ignition --shell /bin/false ignition

# Bring in the unpacked install tree from the unpacker stage.
COPY --from=unpacker /opt/ignition /usr/local/bin/ignition

# ─── Fireball modules, baked in ──────────────────────────────────────────────
#
# The gateway loads modules from user-lib/modules at startup. That directory
# lives in the image layer, not on a volume, so a .modl dropped into a running
# container disappears on the next restart. The chart mounts a /modules PVC and
# values.yaml advertises gateway.modules.autoInstall, but nothing in the chart
# copies /modules into user-lib/modules, so that path installs nothing.
#
# So our modules ship in the image. Every edge gateway then has the viewer the
# moment it boots, with no per-gateway install step and nothing to re-do after a
# pod roll. Verified 2026-09-02: none of the three UT3 edge gateways had the
# viewer installed, because there was no mechanism that could have put it there.
#
# The cost is coupling: the UT3 Schematic Viewer versions independently of
# Ignition (1.22.0 against gateway 8.3.8), so a viewer release now needs an
# image rebuild and a pod roll. That is the deliberate trade.
#
# Built from fireball-industries/UT3-Code via scripts/dev-env/build-modules.sh
# edge. The module is unsigned; the chart already runs the gateway with unsigned
# modules permitted.
COPY modules/*.modl /usr/local/bin/ignition/user-lib/modules/
RUN chmod 0644 /usr/local/bin/ignition/user-lib/modules/*.modl  && ls -la /usr/local/bin/ignition/user-lib/modules/UT3-Schematic-Viewer.modl

# Let container args reach the gateway as Wrapper property overrides.
#
# ignition.sh ignores trailing `wrapper.*=*` arguments unless PASS_THROUGH is
# enabled -- it prints usage and exits 2 instead. The knob ships commented out
# (`#PASS_THROUGH=app_args`). `both` is the value we want: properties first,
# with an optional `--` separator before application arguments. The script's own
# normalizer keeps `both` as-is:
#     elif [ "X${PASS_THROUGH}" != "Xboth" ] ; then PASS_THROUGH=false
# so this must be exactly `both`, not `true`, which collapses to app_args.
#
# Edge charts do not currently pass gateway args, so this is latent here -- but
# the Cloud image hit exactly this and the two images should behave the same.
RUN sed -i 's/^#PASS_THROUGH=.*/PASS_THROUGH=both/' /usr/local/bin/ignition/ignition.sh \
 && grep -q '^PASS_THROUGH=both' /usr/local/bin/ignition/ignition.sh

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
#
# The startup script lives in the entrypoint, NOT in CMD. Container args replace
# CMD, so an inline `bash -c "<script>"` CMD meant any `args:` from a chart threw
# the whole startup away and ran the argument as a command instead. Keeping CMD
# empty makes args arrive as "$@" and get forwarded to the gateway.
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD []
