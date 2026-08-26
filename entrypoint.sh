#!/bin/bash
#
# Container entrypoint for the EmberNet Ignition images (Edge + Cloud).
#
# Why this exists instead of an inline `bash -c` CMD:
#
#   The images used to declare
#       ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "-c"]
#       CMD        ["set -e; cd ...; ./ignition.sh start; ... tail -F ..."]
#   which made the start script the CMD. Container args REPLACE the CMD, so a
#   Kubernetes `args:` list (or `podman run <img> foo=bar`) silently discarded
#   the startup script and asked bash to execute the argument as a command:
#       /bin/bash: line 1: wrapper.java.additional.99=-D...: command not found
#   The container then died instantly. Any chart passing gateway args -- e.g.
#   ut3-ignition-cloud's `gatewayArgs` -- could not deploy these images at all.
#
#   With a real entrypoint, args arrive as "$@" and are forwarded to the
#   gateway rather than replacing it.
#
# What may be passed:
#
#   Java Service Wrapper property overrides, in `wrapper.<name>=<value>` form:
#       wrapper.java.additional.99=-Dignition.allowunsignedmodules=true
#   ignition.sh only accepts these when PASS_THROUGH is enabled, which the
#   image build sets to `both`. Args are validated by ignition.sh itself; a
#   non-`wrapper.*` assignment earns a warning from it rather than silence.
#
set -e

cd /usr/local/bin/ignition

# ignition.sh backgrounds the gateway via the wrapper and exits, so the
# container needs a foreground process afterwards to stay alive.
./ignition.sh start "$@"

# Give the wrapper a moment to create its log before tailing it. `touch`
# guarantees the file exists even if startup was slower than the sleep, so
# `tail -F` never dies on a missing path and take the container with it.
sleep 8
mkdir -p logs
touch logs/wrapper.log

# exec so tail becomes PID 1's child under tini, which reaps the wrapper's
# zombies across gateway restarts (demo mode restarts every ~2h).
exec tail -F logs/wrapper.log
