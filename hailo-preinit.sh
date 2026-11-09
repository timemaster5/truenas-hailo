#!/bin/bash
# PREINIT fast path: load the module built for the running kernel, if there is one.
# No Docker, no network. Exits 0 either way; hailo-ensure.sh handles the rest.
HAILO_HOME=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
# shellcheck source=lib.sh
. "$HAILO_HOME/lib.sh"

set_fw_path || true
module_loaded && exit 0
if ko_matches_kernel; then
  if insmod "$KO"; then log "preinit: loaded $KO"; else log "preinit: insmod failed"; fi
else
  log "preinit: no module for $KVER, waiting for hailo-ensure.sh"
fi
exit 0
