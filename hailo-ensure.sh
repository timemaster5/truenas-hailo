#!/bin/bash
# POSTINIT entrypoint. Idempotent: does nothing when /dev/hailo0 is present.
# Builds hailo_pci.ko for the running kernel in Docker when missing, loads it,
# then restarts the configured TrueNAS apps.
#   --detach   return immediately and run in the background (keeps boot unblocked)
set -uo pipefail

HAILO_HOME=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=lib.sh
. "$HAILO_HOME/lib.sh"

if [[ "${1:-}" == "--detach" ]]; then
  setsid nohup "$0" >/dev/null 2>&1 </dev/null &
  exit 0
fi

CONF=${HAILO_CONF:-$HAILO_HOME/hailo.conf}
[[ -f "$CONF" ]] || CONF=$HAILO_HOME/hailo.conf.example
# shellcheck source=hailo.conf.example
. "$CONF"
: "${DOCKER_WAIT:=600}" "${APPS:=}"

exec 9>"$HAILO_HOME/.lock"
flock -w 3600 9 || { log "lock timeout"; exit 1; }

if module_loaded && [[ -e /dev/hailo0 ]]; then
  exit 0
fi

die() { log "ERROR: $*"; exit 1; }

if module_loaded; then
  log "module loaded but no /dev/hailo0, reloading"
  rmmod hailo_pci || die "rmmod failed"
fi

if ! ko_matches_kernel; then
  log "no module for $KVER, building"
  for ((i = 0; i < DOCKER_WAIT; i += 5)); do
    docker info >/dev/null 2>&1 && break
    sleep 5
  done
  docker info >/dev/null 2>&1 || die "docker not available after ${DOCKER_WAIT}s"

  image=truenas-hailo-builder:$(sha256sum "$HAILO_HOME/build/Dockerfile" | cut -c1-12)
  docker image inspect "$image" >/dev/null 2>&1 \
    || docker build -q -t "$image" "$HAILO_HOME/build" >/dev/null || die "docker build failed"

  mkdir -p "$OUT_DIR" "$HAILO_HOME/cache"
  docker run --rm \
    -e KVER="$KVER" \
    -e HAILO_DRIVER_VERSION="$HAILO_DRIVER_VERSION" \
    -e HAILO_DRIVER_SHA256="$HAILO_DRIVER_SHA256" \
    -e HAILO_FW_URL="${HAILO_FW_URL:-}" \
    -e HAILO_FW_SHA256="${HAILO_FW_SHA256:-}" \
    -v /lib/modules:/lib/modules:ro \
    -v /usr/src:/usr/src:ro \
    -v /boot:/boot:ro \
    -v "$HAILO_HOME/build/build.sh":/build.sh:ro \
    -v "$HAILO_HOME/cache":/cache \
    -v "$OUT_DIR":/out \
    "$image" >>"$HAILO_HOME/hailo.log" 2>&1 || die "build failed, see $HAILO_HOME/hailo.log"
  ko_matches_kernel || die "built module does not match $KVER"
fi

set_fw_path || die "firmware missing in $FW_DIR"
insmod "$KO" || die "insmod failed"
wait_for_device || die "/dev/hailo0 did not appear"
log "loaded $KO"

for app in $APPS; do
  log "restarting app $app"
  midclt call -job app.stop "$app" >/dev/null 2>&1 || log "app.stop $app failed"
  midclt call -job app.start "$app" >/dev/null 2>&1 || log "app.start $app failed"
done
