# shellcheck shell=bash
# Shared helpers, sourced by hailo-ensure.sh and hailo-preinit.sh.

HAILO_HOME=${HAILO_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}
OUT_DIR=$HAILO_HOME/out
KVER=$(uname -r)
KO=$OUT_DIR/$KVER/hailo_pci.ko
FW_DIR=$OUT_DIR/firmware

log() {
  logger -t truenas-hailo -- "$*" 2>/dev/null || true
  printf '%s %s\n' "$(date -Is)" "$*" >>"$HAILO_HOME/hailo.log" 2>/dev/null || true
}

ko_matches_kernel() {
  [[ -f "$KO" ]] && [[ "$(modinfo -F vermagic "$KO" 2>/dev/null | cut -d' ' -f1)" == "$KVER" ]]
}

set_fw_path() {
  [[ -d "$FW_DIR/hailo" ]] && printf '%s' "$FW_DIR/" >/sys/module/firmware_class/parameters/path
}

module_loaded() { [[ -d /sys/module/hailo_pci ]]; }

wait_for_device() {
  local i
  for ((i = 0; i < 30; i++)); do
    [[ -e /dev/hailo0 ]] && return 0
    sleep 1
  done
  return 1
}

load_conf() {
  local conf=${HAILO_CONF:-$HAILO_HOME/hailo.conf}
  [[ -f "$conf" ]] || conf=$HAILO_HOME/hailo.conf.example
  # shellcheck source=hailo.conf.example
  . "$conf"
}

# Driver version plus a hash of its patches; a changed id forces a rebuild.
build_id() {
  local h
  h=$(cat "$HAILO_HOME/patches/$HAILO_DRIVER_VERSION"/*.patch 2>/dev/null | sha256sum | cut -c1-12)
  printf '%s-%s' "$HAILO_DRIVER_VERSION" "$h"
}

build_current() {
  [[ "$(cat "$OUT_DIR/$KVER/build-id" 2>/dev/null)" == "$(build_id)" ]]
}
