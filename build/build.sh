#!/usr/bin/env bash
# Runs inside the builder container. Host trees are mounted read-only:
#   /lib/modules, /usr/src, /boot   (kernel headers, config)
#   /cache (rw)                     downloaded source and firmware
#   /out   (rw)                     results
# Env: KVER HAILO_DRIVER_VERSION HAILO_DRIVER_SHA256 HAILO_FW_URL HAILO_FW_SHA256
set -euo pipefail

: "${KVER:?}" "${HAILO_DRIVER_VERSION:?}" "${HAILO_DRIVER_SHA256:?}"

KBUILD=/lib/modules/${KVER}/build
if [[ ! -d "$KBUILD" ]]; then
  flavor=production
  [[ "$KVER" == *debug* ]] && flavor=debug
  KBUILD=$(find /usr/src -maxdepth 1 -name "linux-headers-*${flavor}*" | head -n1)
fi
[[ -d "$KBUILD" ]] || { echo "no kernel headers for ${KVER}" >&2; exit 1; }
echo "headers: ${KBUILD}"

# The header tree must be writable for modules_prepare, so work on a copy.
rsync -aH "${KBUILD}/" /work/kbuild/
if [[ ! -f /work/kbuild/.config ]]; then
  cp "/boot/config-${KVER}" /work/kbuild/.config
fi

kr=$(make -s -C /work/kbuild kernelrelease)
if [[ "$kr" != "$KVER" ]]; then
  echo "headers are for ${kr}, running kernel is ${KVER}; refusing (modversions would reject the module)" >&2
  exit 1
fi
if [[ ! -f /work/kbuild/include/generated/autoconf.h || ! -f /work/kbuild/include/config/auto.conf ]]; then
  make -C /work/kbuild olddefconfig >/dev/null
  make -C /work/kbuild modules_prepare
fi

mkdir -p /cache
src=/cache/hailort-drivers-${HAILO_DRIVER_VERSION}.tar.gz
if ! echo "${HAILO_DRIVER_SHA256}  ${src}" | sha256sum -c - >/dev/null 2>&1; then
  curl -fL --retry 5 --retry-delay 2 -o "$src" \
    "https://github.com/hailo-ai/hailort-drivers/archive/refs/tags/v${HAILO_DRIVER_VERSION}.tar.gz"
  echo "${HAILO_DRIVER_SHA256}  ${src}" | sha256sum -c -
fi
tar -xzf "$src" -C /work
make -C "/work/hailort-drivers-${HAILO_DRIVER_VERSION}/linux/pcie" all \
  kernelver="${KVER}" KERNEL_DIR=/work/kbuild

mkdir -p "/out/${KVER}"
cp "/work/hailort-drivers-${HAILO_DRIVER_VERSION}/linux/pcie/hailo_pci.ko" "/out/${KVER}/hailo_pci.ko"

fw=/out/firmware/hailo/hailo8_fw.bin
if [[ -n "${HAILO_FW_URL:-}" && ! -s "$fw" ]]; then
  mkdir -p /out/firmware/hailo
  curl -fL --retry 5 --retry-delay 2 -o "${fw}.part" "$HAILO_FW_URL"
  if [[ -n "${HAILO_FW_SHA256:-}" ]]; then
    echo "${HAILO_FW_SHA256}  ${fw}.part" | sha256sum -c -
  fi
  mv "${fw}.part" "$fw"
fi
echo "built ${KVER}"
