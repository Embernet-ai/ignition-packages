# Embernet Ignition Packages

Inductive Automation Ignition runtimes — Edge (ARM64 + x86-64) and
Cloud/Standard (x86-64) — packaged for Podman Quadlet deployment on
EmberNet edge appliances and UT3 control-plane nodes.

## Releases

This repository hosts the upstream Ignition install artifacts as GitHub
Releases. Each release tag `vX.Y.Z` carries one or more assets.

| Tag      | Platform        | Asset name | Edition |
|----------|-----------------|------------|---------|
| `v8.3.8` | Linux x86-64    | `ignition-8.3.8-linux-64-installer.run` (~2.0 GB) | Standard (BitRock installer) |
| `v8.3.8` | Linux x86-64    | `ignition-cloud-8.3.8-linux-64-installer.run` (~1.88 GB) | Cloud (BitRock installer) |
| `v8.3.8` | Linux x86-64    | `Ignition-Edge-linux-x86-64-8.3.8.zip` (~1.85 GB) | Edge (portable ZIP) |
| `v8.3.8` | Linux ARM64     | `Ignition-linux-aarch-64-8.3.8.zip` (~1.90 GB) | Standard (portable ZIP) |
| `v8.3.8` | Linux ARM64     | `Ignition-Edge-linux-aarch-64-8.3.8.zip` (~1.86 GB) | Edge (portable ZIP) |
| `v8.3.8` | Linux ARM32     | `Ignition-linux-armhf-32-8.3.8.zip` (~1.90 GB) | Standard (portable ZIP) |
| `v8.3.8` | Linux ARM32     | `Ignition-Edge-linux-armhf-32-8.3.8.zip` (~1.86 GB) | Edge (portable ZIP) |

## Container images

Two container images are built + published from this repo:

**`ghcr.io/embernet-ai/ignition-edge`** — built from `Containerfile`
(ARM64 portable ZIP) on every commit to `main`. Tags:
```
ghcr.io/embernet-ai/ignition-edge:8.3.8
ghcr.io/embernet-ai/ignition-edge:latest
ghcr.io/embernet-ai/ignition-edge:main
```

Those three are a manifest list for linux/amd64 and linux/arm64, so the
same tag works on an x86 edge VM and on a Pi. `build.yml` pushes the amd64
image and `build-arm64.yml` pushes `:8.3.8-arm64`, and after either one
finishes `edge-manifest.yml` joins the two per-arch images into the list.
The per-arch tags (`:8.3.8-amd64`, `:8.3.8-arm64`, `:main-amd64`,
`:main-arm64`) still point at single images if you want to pin an arch.
Until September 2026 the canonical tags were amd64 only and a Pi pulling
`:latest` died with exec format error. Never delete an old digest from the
package: UT3 cp02 pins this image by digest.

**`ghcr.io/embernet-ai/ignition-cloud`** — built from
`Containerfile.cloud` (x86-64 .run installer, unattended mode) on
every commit to `main`. Tags:
```
ghcr.io/embernet-ai/ignition-cloud:8.3.8
ghcr.io/embernet-ai/ignition-cloud:latest
ghcr.io/embernet-ai/ignition-cloud:main
```

Cloud (Standard edition) is x86-64 only — there is no aarch64 .run
published for v8.3.4. Both Edge and Cloud can run **co-resident on
the same host** via Quadlet by remapping ports — see UT3 cp02's
[deploy-ut3-cp02.sh](https://github.com/Fireball-Red-Team/deployment/blob/main/deploy-ut3-cp02.sh)
where Edge keeps defaults (8088/8043/8060) and Cloud is remapped to
8089/8044/8061.

**`ghcr.io/embernet-ai/ignition`** is the full edition (Standard), built
from `Containerfile.standard` for linux/amd64 and linux/arm64. Tags:
```
ghcr.io/embernet-ai/ignition:8.3.8
ghcr.io/embernet-ai/ignition:latest
ghcr.io/embernet-ai/ignition:main
```

Those three are a manifest list. IA ships the full edition as a `.run`
installer on x86-64 and as a portable ZIP on aarch64, and the v8.3.8 release
here carries both, so the amd64 image comes from
`ignition-8.3.8-linux-64-installer.run` and the arm64 image from
`Ignition-linux-aarch-64-8.3.8.zip`. `build-standard.yml` builds each one on a
native runner (no QEMU), boots the gateway and waits for RUNNING on 8.3.8
before it pushes `:8.3.8-amd64` and `:8.3.8-arm64`, then joins them. Unlike
Edge and Cloud, this image runs as `ignition` (uid 999) by default and its
install tree belongs to that user, so the EmberNet Ignition chart runs it with
no root at all. Default ports are IA's own: 8088, 8043, 8060.

The image:
- Includes Ignition's bundled JRE (no separate Java install needed).
- Pre-loads every standard module: Vision, Perspective, OPC UA, the
  full driver suite (Allen-Bradley, Siemens, Modbus, Mitsubishi,
  Omron, BACnet, DNP3, Micro800, UDP/TCP), Historian, Alarm
  Notification, Symbol Factory, Web Developer, Enterprise Admin.
- Defaults to demo mode (no license file mounted). Operator activates
  via web UI on first boot, or mounts a license file later.
- EULA pre-accepted via `ACCEPT_IGNITION_EULA=Y`.
- Admin user pre-set to `admin` / `embernet` (override per-deployment
  via the deploy script's `--ignition-admin-password` flag).

## Why containerize?

Inductive Automation publishes both a Linux installer (`.deb`/`.rpm`)
and a portable ZIP. Installing the `.deb` on openSUSE MicroOS (RPM,
read-only btrfs root, transactional-update model) is non-viable. The
ZIP is the supported "drop in a directory and run `./ignition.sh`"
distribution — perfect for a container layer. The actual runtime is
identical to a host install; the JRE, libs, and modules are all
bundled in the ZIP.

This pattern matches our other ARM64 runtime images:
- [`Embernet-ai/embernet-network-controller-container`](https://github.com/Embernet-ai/embernet-network-controller-container)
- [`Embernet-ai/codesys-linux-arm-64`](https://github.com/Embernet-ai/codesys-linux-arm-64)

## Use it on a Pi

Don't run this manually — the deploy at
[Fireball-Red-Team/deploy-eci-ember-node](https://github.com/Fireball-Red-Team/deploy-eci-ember-node)
pulls and starts this image as part of the embernode-arm-NNNN
node-deploy. See its `.agent/workflows/deploy-embernet-node.md` for
the full sequence.

To pull and run by hand for local testing:

```bash
sudo podman pull ghcr.io/embernet-ai/ignition-edge:latest

sudo podman run -d --name ignition-test \
  --privileged \
  -p 8088:8088 -p 8043:8043 -p 8060:8060/udp \
  -e ACCEPT_IGNITION_EULA=Y \
  -e GATEWAY_ADMIN_USERNAME=admin \
  -e GATEWAY_ADMIN_PASSWORD=embernet \
  -e IGNITION_EDITION=edge \
  -v /tmp/ignition-data:/usr/local/bin/ignition/data:Z \
  ghcr.io/embernet-ai/ignition-edge:latest

# Web UI
open http://<host-ip>:8088
```

**First-run note:** if you're mounting an empty `/tmp/ignition-data`
directory, you must seed it from the image first or the container
will crash with `FATAL: Configuration file gateway.xml_clean not
found`:

```bash
sudo podman run --rm \
  -v /tmp/ignition-data:/seed:Z \
  --entrypoint sh \
  ghcr.io/embernet-ai/ignition-edge:latest \
  -c 'cp -a /usr/local/bin/ignition/data/. /seed/'
```

The deploy script handles this seeding automatically.

## CI

- **Trigger**: push to `main` or `develop` (paths-filtered to
  `Containerfile` / `.github/workflows/build.yml` so doc-only changes
  don't trigger a 25-min QEMU rebuild). Manual runs via
  `workflow_dispatch` accept an `ignition_version` input for
  republishing older versions.
- **Build**: multi-stage. Stage 1 downloads the ZIP and unpacks to
  `/opt/ignition`. Stage 2 (debian:bookworm-slim runtime base) does
  `COPY --from=unpacker /opt/ignition /usr/local/bin/ignition`. The
  multi-stage drops the ZIP and unpack tools from the final image.
- **Push**: on push events to main/develop, manifest pushed to
  `ghcr.io/embernet-ai/ignition-edge:<branch>`. On main pushes,
  also `:latest` and the pinned version tag (currently `:8.3.6`).
- **Smoke test**: confirms install layout (`ignition.sh`,
  `ignition-gateway`, `data/gateway.xml_clean`,
  `user-lib/modules/`) is present in the image.
- **Disk**: runner reclaims ~10 GB before build to fit the ZIP +
  extracted tree + image layers.
- **Concurrency**: at most one build per ref at a time.

## Bumping the Ignition version

1. Upload the new `Ignition-Edge-linux-aarch-64-X.Y.Z.zip` as a
   release asset under tag `vX.Y.Z`.
2. Update the `IGNITION_VERSION` default in `Containerfile` and
   `.github/workflows/build.yml`.
3. Commit + push to `main`. CI rebuilds and republishes
   `:latest`, `:main`, and `:X.Y.Z`.

## Resource budget

Sized for a Pi 4/5 co-tenanting CodeSys, K3s agent, and the ForgeNET
controller. Defaults from the deploy script:

| Knob   | Value | Source |
|--------|-------|--------|
| Memory | 1.5 GiB | `IGNITION_MEMORY` in `deploy-embernet-node-microos.sh` |
| CPU    | 1.5 core | `IGNITION_CPUS` in `deploy-embernet-node-microos.sh` |

Override per-node by passing `--ignition-memory` / `--ignition-cpus`
flags to the deploy script (or editing the per-node wrapper).
