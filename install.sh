#!/bin/bash
# Prints what it would do. Nothing is changed without --apply.
#   install.sh [--apply] [--dest DIR]
#   install.sh --uninstall [--apply]      removes the init tasks only, never the files
set -euo pipefail

SRC=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEST=/root/truenas-hailo
APPLY=0
UNINSTALL=0
TAG="truenas-hailo"

while (($#)); do
  case $1 in
    --apply) APPLY=1 ;;
    --uninstall) UNINSTALL=1 ;;
    --dest) DEST=${2:?}; shift ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

run() {
  printf '+ %s\n' "$*"
  ((APPLY)) && "$@"
  return 0
}

existing=$(midclt call initshutdownscript.query "[[\"comment\",\"^\",\"$TAG\"]]")

if ((UNINSTALL)); then
  ids=$(printf '%s' "$existing" | python3 -c 'import json,sys; print(*[t["id"] for t in json.load(sys.stdin)])')
  for id in $ids; do
    run midclt call initshutdownscript.delete "$id"
  done
  echo "Files in $DEST are left in place."
  ((APPLY)) || echo "(dry run, pass --apply)"
  exit 0
fi

if [[ "$existing" != "[]" ]]; then
  echo "Init tasks with comment '$TAG' already exist, not adding more:" >&2
  echo "$existing" >&2
  exit 1
fi

run mkdir -p "$DEST/build"
run cp "$SRC/hailo-ensure.sh" "$SRC/hailo-preinit.sh" "$SRC/lib.sh" "$DEST/"
run cp "$SRC/build/Dockerfile" "$SRC/build/build.sh" "$DEST/build/"
if [[ ! -f "$DEST/hailo.conf" ]]; then
  run cp "$SRC/hailo.conf.example" "$DEST/hailo.conf"
fi
run chmod 755 "$DEST/hailo-ensure.sh" "$DEST/hailo-preinit.sh"

run midclt call initshutdownscript.create \
  "{\"type\":\"COMMAND\",\"command\":\"$DEST/hailo-preinit.sh\",\"when\":\"PREINIT\",\"enabled\":true,\"timeout\":20,\"comment\":\"$TAG: load module for running kernel\"}"
run midclt call initshutdownscript.create \
  "{\"type\":\"COMMAND\",\"command\":\"$DEST/hailo-ensure.sh --detach\",\"when\":\"POSTINIT\",\"enabled\":true,\"timeout\":10,\"comment\":\"$TAG: build and load if missing\"}"

((APPLY)) || echo "(dry run, pass --apply)"
